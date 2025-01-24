#!/bin/bash
set -e

CONNECTION_NAME="$WLAN_INTERFACE-ap"

# Check if the connection exists
if nmcli connection show "$CONNECTION_NAME" > /dev/null 2>&1; then
    # Bring the connection down if it is active
    if nmcli connection show --active | grep -q "$CONNECTION_NAME"; then
        nmcli connection down "$CONNECTION_NAME"
    fi

    # Remove the connection entirely
    nmcli connection delete "$CONNECTION_NAME"
fi

killall sleep
