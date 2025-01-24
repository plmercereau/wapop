#!/bin/bash
set -e

CONNECTION_NAME="$WLAN_INTERFACE-ap"
CHANNEL=6 # TODO implement best channel picker, and 6GHz support

# Check if the connection exists
if nmcli connection show "$CONNECTION_NAME" > /dev/null 2>&1; then
    # Check if settings match
    CURRENT_SSID=$(nmcli -g 802-11-wireless.ssid connection show "$CONNECTION_NAME")
    CURRENT_PSK=$(nmcli -g 802-11-wireless-security.psk connection show "$CONNECTION_NAME")

    if [[ "$CURRENT_SSID" == "$SSID" && "$CURRENT_PSK" == "$PSK" ]]; then
        echo "Connection '$CONNECTION_NAME' is already configured correctly. Exiting."
        exit 0
    else
        echo "Updating connection '$CONNECTION_NAME' with new settings. SSID: $SSID"
        nmcli connection modify "$CONNECTION_NAME" 802-11-wireless.ssid "$SSID" \
            802-11-wireless-security.psk "$PSK"
    fi
else
    # Create a new connection if it doesn't exist
    echo "Creating new connection '$CONNECTION_NAME'. SSID: $SSID"
    nmcli connection add type wifi \
        ifname "$WLAN_INTERFACE" \
        con-name "$CONNECTION_NAME" \
        ssid "$SSID" \
        mode ap \
        ipv4.method shared \
        wifi.band bg \
        wifi.channel $CHANNEL \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$PSK" \
        connection.master "$BRIDGE_INTERFACE" \
        connection.slave-type bridge
fi

# Bring up the connection
nmcli connection up "$CONNECTION_NAME"

# Signal that the AP is ready - it is then used in the pod as a readiness probe
echo "ready" > /tmp/ready

# Keep the script running so the pod doesn't exit. It is a trade-off between using a daemonset and a system of jobs.
sleep infinity
