#!/bin/bash
set -e

CONNECTION_NAME="$WLAN_INTERFACE-ap"

# Check if the connection exists
if nmcli connection show "${CONNECTION_NAME}_24ghz" > /dev/null 2>&1; then
    # Bring the connection down if it is active
    if nmcli connection show --active | grep -q "${CONNECTION_NAME}_24ghz"; then
        nmcli connection down "${CONNECTION_NAME}_24ghz"
    fi

    # Remove the connection entirely
    nmcli connection delete "${CONNECTION_NAME}_24ghz"
fi
if nmcli connection show "${CONNECTION_NAME}_5ghz" > /dev/null 2>&1; then
    # Bring the connection down if it is active
    if nmcli connection show --active | grep -q "${CONNECTION_NAME}_5ghz"; then
        nmcli connection down "${CONNECTION_NAME}_5ghz"
    fi

    # Remove the connection entirely
    nmcli connection delete "${CONNECTION_NAME}_5ghz"
fi

killall sleep
