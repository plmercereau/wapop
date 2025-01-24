allow_k8s_contexts('rpi')

docker_build('plmercereau/wapop', '.')

k8s_yaml(kustomize('./config/samples'))
