package controller

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"time"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
	"sigs.k8s.io/yaml"

	"github.com/plmercereau/wapop/api/v1alpha1"
)

var settingsName = "wifi-settings"

// NodeReconciler reconciles a Node object
type NodeReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=wifi.networking.platyplus.io,resources=accesspoints,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=wifi.networking.platyplus.io,resources=accesspoints/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=wifi.networking.platyplus.io,resources=accesspoints/finalizers,verbs=update
// +kubebuilder:rbac:groups=core,resources=nodes,verbs=get;list;watch
// +kubebuilder:rbac:groups="",resources=secrets;configmaps,verbs=get;list;watch
// +kubebuilder:rbac:groups=batch,resources=jobs,verbs=get;list;watch;create;update;patch;delete

func (r *NodeReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	ns := getNamespace(ctx)
	// get configurations
	config := &corev1.ConfigMap{}
	if err := r.Get(ctx, types.NamespacedName{
		Name:      settingsName,
		Namespace: ns,
	}, config); err != nil {
		logger.Error(err, "unable to fetch ConfigMap", "name", settingsName)
		return ctrl.Result{}, err
	}

	secret := &corev1.Secret{}
	if err := r.Get(ctx, types.NamespacedName{
		Name:      settingsName,
		Namespace: ns,
	}, secret); err != nil {
		log.FromContext(ctx).Error(err, "unable to fetch Secret", "name", settingsName)
		return ctrl.Result{}, err
	}

	logger.Info("Reconciling Node", "name", req.Name)

	// get node
	node := &corev1.Node{}
	if err := r.Get(ctx, req.NamespacedName, node); err != nil {
		logger.Error(err, "unable to fetch Node")
		return ctrl.Result{}, err
	}

	activate := false
	// Get the nodeSelector from the ConfigMap
	nodeSelectorStr, ok := config.Data["nodeSelector"]
	if !ok {
		logger.Info("nodeSelector key missing in ConfigMap data. The node is selected.")
		activate = true
	} else {
		nodeSelector := &metav1.LabelSelector{}
		if err := yaml.Unmarshal([]byte(nodeSelectorStr), nodeSelector); err != nil {
			logger.Error(err, "unable to unmarshal nodeSelector")
			return ctrl.Result{}, err
		}
		// check if the node matches the nodeSelector
		selector, err := metav1.LabelSelectorAsSelector(nodeSelector)
		if err != nil {
			logger.Error(err, "unable to convert LabelSelector to Selector")
			return ctrl.Result{}, err
		}
		activate = selector.Matches(labels.Set(node.Labels))
	}

	// check if the corresponding AccessPoint exists. If not, create it
	ap := &v1alpha1.AccessPoint{}
	accessPointName := client.ObjectKey{
		Name: node.Name,
	}
	if err := r.Get(ctx, accessPointName, ap); err != nil {
		if client.IgnoreNotFound(err) == nil {
			// AccessPoint does not exist, create it
			ap = &v1alpha1.AccessPoint{
				ObjectMeta: ctrl.ObjectMeta{
					Name: node.Name,
				},
				Spec: v1alpha1.AccessPointSpec{
					// Name: node.Name,
				},
			}
			controllerutil.SetControllerReference(node, ap, r.Scheme)
			if err := r.Create(ctx, ap); err != nil {
				logger.Error(err, "unable to create AccessPoint", "name", accessPointName)
				return ctrl.Result{}, err
			}
			logger.Info("AccessPoint created", "name", accessPointName)
		} else {
			logger.Error(err, "unable to get AccessPoint", "name", accessPointName)
			return ctrl.Result{}, err
		}
	}

	hash := hashValues(node.Status.NodeInfo.BootID, activate, config.Data, secret.Data)
	// Don't continue if the hash is the same
	if ap.Status.Hash == hash {
		logger.Info("AccessPoint already up to date")
		return ctrl.Result{}, nil
	}

	jobName := "wifi-job-" + node.Name // TODO
	// Get the job. if it exists, delete it
	job := &batchv1.Job{}
	if err := r.Get(ctx, types.NamespacedName{
		Name:      jobName,
		Namespace: ns,
	}, job); err == nil {
		if err := r.Delete(ctx, job); err != nil {
			logger.Error(err, "unable to delete Job")
			return ctrl.Result{}, err
		}
		return ctrl.Result{RequeueAfter: time.Second}, nil
	}

	command := "/app/enable-ap.sh"
	if !activate {
		command = "/app/disable-ap.sh"
	}

	job = &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      jobName,
			Namespace: ns,
		},
		Spec: batchv1.JobSpec{
			// set TTLSecondsAfterFinished to 1 day
			TTLSecondsAfterFinished: func(i32 int32) *int32 { return &i32 }(86400),
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					HostNetwork: true,
					Containers: []corev1.Container{
						{
							Name:  "configure",
							Image: "registry.suse.com/suse/sl-micro/6.0/baremetal-os-container:2.1.3-4.7",
							Command: []string{
								"/bin/sh",
								"-c",
								command,
							},
							SecurityContext: &corev1.SecurityContext{
								Privileged: func(b bool) *bool { return &b }(true),
							},
							VolumeMounts: []corev1.VolumeMount{
								{
									Name:      "host-etc-nm",
									MountPath: "/etc/NetworkManager",
								},
								{
									Name:      "dbus-socket",
									MountPath: "/var/run/dbus/system_bus_socket",
								},
								{
									Name:      "scripts",
									MountPath: "/app",
								},
							},
							Env: []corev1.EnvVar{
								{
									Name: "ssid",
									ValueFrom: &corev1.EnvVarSource{
										ConfigMapKeyRef: &corev1.ConfigMapKeySelector{
											Key: "ssid",
											LocalObjectReference: corev1.LocalObjectReference{
												Name: settingsName,
											},
										},
									},
								},
							},
							EnvFrom: []corev1.EnvFromSource{
								{
									SecretRef: &corev1.SecretEnvSource{
										LocalObjectReference: corev1.LocalObjectReference{
											Name: settingsName,
										},
									},
								},
							},
						},
					},
					Volumes: []corev1.Volume{
						{
							Name: "host-etc-nm",
							VolumeSource: corev1.VolumeSource{
								HostPath: &corev1.HostPathVolumeSource{
									Path: "/etc/NetworkManager",
								},
							},
						},
						{
							Name: "dbus-socket",
							VolumeSource: corev1.VolumeSource{
								HostPath: &corev1.HostPathVolumeSource{
									Path: "/var/run/dbus/system_bus_socket",
								},
							},
						},
						{
							Name: "scripts",
							VolumeSource: corev1.VolumeSource{
								ConfigMap: &corev1.ConfigMapVolumeSource{
									DefaultMode: func(i int32) *int32 { return &i }(0o755),
									LocalObjectReference: corev1.LocalObjectReference{
										Name: "wapop-scripts",
									},
								},
							},
						},
					},
					RestartPolicy: corev1.RestartPolicyNever,
				},
			},
		},
	}
	controllerutil.SetControllerReference(ap, job, r.Scheme)
	if err := r.Create(ctx, job); err != nil {
		logger.Error(err, "unable to create Job")
		return ctrl.Result{}, err
	}
	// update the AccessPoint status
	ap.Status.Hash = hash
	if err := r.Status().Update(ctx, ap); err != nil {
		logger.Error(err, "unable to update AccessPoint status")
		return ctrl.Result{}, err
	}

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *NodeReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&corev1.Node{}).
		Owns(&v1alpha1.AccessPoint{}).
		Owns(&batchv1.Job{}).
		Watches(
			&corev1.Secret{},
			handler.EnqueueRequestsFromMapFunc(lookupSettings(mgr.GetClient())),
		).
		Watches(
			&corev1.ConfigMap{},
			handler.EnqueueRequestsFromMapFunc(lookupSettings(mgr.GetClient())),
		).
		Complete(r)
}

func lookupSettings(c client.Client) func(ctx context.Context, s client.Object) []reconcile.Request {
	return func(ctx context.Context, s client.Object) []reconcile.Request {
		var requests []reconcile.Request
		nodeList := &corev1.NodeList{}
		if err := c.List(ctx, nodeList); err != nil {
			log.FromContext(ctx).Error(err, "unable to list nodes")
			return requests
		}

		operatorNamespace := getNamespace(ctx)
		if s.GetName() == settingsName && s.GetNamespace() == operatorNamespace {
			for _, node := range nodeList.Items {
				requests = append(requests, reconcile.Request{
					NamespacedName: types.NamespacedName{
						Name: node.GetName(),
					},
				})
			}
		}
		return requests
	}
}

func getNamespace(ctx context.Context) string {
	namespaceFile := "/var/run/secrets/kubernetes.io/serviceaccount/namespace"

	if _, err := os.Stat(namespaceFile); os.IsNotExist(err) {
		log.FromContext(ctx).Error(err, "Namespace file does not exist")

	}

	namespace, err := os.ReadFile(namespaceFile)
	if err != nil {
		log.FromContext(ctx).Error(err, "Failed to read namespace file")
	}

	return string(namespace)
}

// hashValues computes a hash of the combined input values.
// Accepts a variable number of inputs of any type.
func hashValues(values ...interface{}) string {
	// Create a single slice to hold all serialised values
	var combinedData []byte

	for _, value := range values {
		// Serialise each value to JSON
		data, err := json.Marshal(value)
		if err != nil {
			// Handle serialisation errors
			panic(fmt.Sprintf("failed to serialise value for hashing: %v", err))
		}

		// Append the serialised data to the combined data
		combinedData = append(combinedData, data...)
	}

	// Compute the SHA-256 hash of the combined data
	hash := sha256.Sum256(combinedData)

	// Convert the hash to a hexadecimal string
	return fmt.Sprintf("%x", hash)
}
