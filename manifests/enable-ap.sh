#!/usr/bin/env bash
set -e

CONNECTION_NAME="$WLAN_INTERFACE-ap"

# Preferred channels for 2.4 GHz and 5 GHz
PREFERRED_24=(1 6 11 2 3 4 5 7 8 9 10)
PREFERRED_5=(36 40 44 48 149 153 157 161 165)

# Get all channels currently used by the machine
current_channels=$(nmcli -t -f active,chan dev wifi | grep '^yes' | awk -F: '{print $2}' | tr '\n' ' ')

# Function to check if a channel is in the list of current channels
is_current_channel() {
    local channel=$1
    for used_channel in $current_channels; do
        if [[ "$channel" == "$used_channel" ]]; then
            return 0  # Channel is in use
        fi
    done
    return 1  # Channel is not in use
}

# Function to find the best channel
# TODO the algorithm is not ideal at all, it should be improved
find_best_channel() {
    local preferred_channels=($1)
    local freq_band=$2

    # Get Wi-Fi scan results using nmcli
    scan_results=$(nmcli -t -f IN-USE,SSID,CHAN,FREQ,SIGNAL dev wifi list)

    declare -A channel_intensity

    # Parse scan results
    while IFS=: read -r in_use ssid chan freq signal; do
        # Remove "MHz" from the frequency value
        freq=${freq// MHz/}

        # Skip the channel if it's currently used by the machine
        if is_current_channel "$chan"; then
            continue
        fi

        # Check if the channel is in the frequency band (2.4 GHz or 5 GHz)
        if [[ "$freq_band" == "2.4" && $freq -lt 3000 ]] || [[ "$freq_band" == "5" && $freq -ge 3000 ]]; then
            # Add the signal intensity for the channel
            channel_intensity[$chan]=$((channel_intensity[$chan] + signal))
        fi
    done <<< "$scan_results"

    # Iterate over preferred channels to find the best one
    for channel in "${preferred_channels[@]}"; do
        if [[ -z ${channel_intensity[$channel]} ]]; then
            echo "$channel"
            return
        fi
    done

    echo "No preferred channel available"
}

# Check if the connection exists
if nmcli connection show "${CONNECTION_NAME}_24ghz" > /dev/null 2>&1; then
    CURRENT_SSID=$(nmcli -g 802-11-wireless.ssid connection show "${CONNECTION_NAME}_5ghz")
    CURRENT_PSK=$(nmcli -g 802-11-wireless-security.psk connection show "${CONNECTION_NAME}_5ghz")
    if [[ "$CURRENT_SSID" == "$SSID" && "$CURRENT_PSK" == "$PSK" ]]; then
        echo "Connection '${CONNECTION_NAME}_5ghz' is already configured."
    else
        echo "Updating connection '${CONNECTION_NAME}_5ghz' with new settings. SSID: $SSID"
        nmcli connection modify "${CONNECTION_NAME}_5ghz" 802-11-wireless.ssid "$SSID" \
            802-11-wireless-security.psk "$PSK"
        # Bring up the connection
        nmcli connection up "${CONNECTION_NAME}_5ghz"
    fi

    CURRENT_SSID=$(nmcli -g 802-11-wireless.ssid connection show "${CONNECTION_NAME}_24ghz")
    CURRENT_PSK=$(nmcli -g 802-11-wireless-security.psk connection show "${CONNECTION_NAME}_24ghz")

    if [[ "$CURRENT_SSID" == "$SSID" && "$CURRENT_PSK" == "$PSK" ]]; then
        echo "Connection '${CONNECTION_NAME}_24ghz' is already configured."
    else
        echo "Updating connection '${CONNECTION_NAME}_24ghz' with new settings. SSID: $SSID"
        nmcli connection modify "${CONNECTION_NAME}_24ghz" 802-11-wireless.ssid "$SSID" \
            802-11-wireless-security.psk "$PSK"
        # Bring up the connection
        nmcli connection up "${CONNECTION_NAME}_24ghz"
    fi
else
    # Find the best 5 GHz channel
    BEST_CHANNEL_5=$(find_best_channel "${PREFERRED_5[*]}" "5")

    # Find the best 2.4 GHz channel
    BEST_CHANNEL_24=$(find_best_channel "${PREFERRED_24[*]}" "2.4")

    # Display the results
    echo "Best 5 GHz Channel: $BEST_CHANNEL_5"
    echo "Best 2.4 GHz Channel: $BEST_CHANNEL_24"

    # Create a new connection if it doesn't exist
    echo "Creating new connection '$CONNECTION_NAME'. SSID: $SSID"
    nmcli connection add type wifi \
        ifname "$WLAN_INTERFACE" \
        con-name "${CONNECTION_NAME}_5ghz" \
        ssid "$SSID" \
        mode ap \
        ipv4.method shared \
        wifi.band a \
        wifi.channel $BEST_CHANNEL_5 \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$PSK" \
        connection.master "$BRIDGE_INTERFACE" \
        connection.slave-type bridge

    nmcli connection add type wifi \
        ifname "$WLAN_INTERFACE" \
        con-name "${CONNECTION_NAME}_24ghz" \
        ssid "$SSID" \
        mode ap \
        ipv4.method shared \
        wifi.band bg \
        wifi.channel $BEST_CHANNEL_24 \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$PSK" \
        connection.master "$BRIDGE_INTERFACE" \
        connection.slave-type bridge

    # Bring up the connections
    # Dual channel may not be supported by all devices, so we bring up the 5 GHz connection first
    nmcli connection up "${CONNECTION_NAME}_5ghz"
    nmcli connection up "${CONNECTION_NAME}_24ghz"
fi


# Signal that the AP is ready - it is then used in the pod as a readiness probe
echo "ready" > /tmp/ready

# Keep the script running so the pod doesn't exit. It is a trade-off between using a daemonset and a system of jobs.
sleep infinity
