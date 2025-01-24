#!/bin/bash

SSID="$ssid"
PSK="$psk"
IFNAME="$wlan_interface"
MASTER="$bridge_interface"
CON_NAME="$IFNAME-ap"
CHANNEL=6 # TODO implement best channel picker, and 6GHz support

# Check if the connection exists
if nmcli connection show "$CON_NAME" > /dev/null 2>&1; then
    # Check if settings match
    CURRENT_SSID=$(nmcli -g 802-11-wireless.ssid connection show "$CON_NAME")
    CURRENT_PSK=$(nmcli -g 802-11-wireless-security.psk connection show "$CON_NAME")

    if [[ "$CURRENT_SSID" == "$SSID" && "$CURRENT_PSK" == "$PSK" ]]; then
        echo "Connection '$CON_NAME' is already configured correctly. Exiting."
        exit 0
    else
        echo "Updating connection '$CON_NAME' with new settings. SSID: $SSID"
        nmcli connection modify "$CON_NAME" 802-11-wireless.ssid "$SSID" \
            802-11-wireless-security.psk "$PSK"
    fi
else
    # Create a new connection if it doesn't exist
    echo "Creating new connection '$CON_NAME'. SSID: $SSID"
    nmcli connection add type wifi \
        ifname "$IFNAME" \
        con-name "$CON_NAME" \
        ssid "$SSID" \
        mode ap \
        ipv4.method shared \
        wifi.band bg \
        wifi.channel $CHANNEL \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$PSK" \
        connection.master "$MASTER" \
        connection.slave-type bridge
fi

# Bring up the connection
nmcli connection up "$CON_NAME"

# Signal that the AP is ready - it is then used in the pod as a readiness probe
echo "ready" > /tmp/ready

# Keep the script running so the pod doesn't exit. It is a trade-off between using a daemonset and a system of jobs.
sleep infinity