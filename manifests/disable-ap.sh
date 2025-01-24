#!/bin/bash
set -e

CONNECTION_NAME="$WLAN_INTERFACE-ap"

# Check if the connection exists
if nmcli connection show "$CONNECTION_NAME" > /dev/null 2>&1; then
    echo "Disabling connection '$CONNECTION_NAME'..."
    # Bring the connection down if it's active
    if nmcli connection show --active | grep -q "$CONNECTION_NAME"; then
        nmcli connection down "$CONNECTION_NAME"
        echo "Connection '$CONNECTION_NAME' has been deactivated."
    else
        echo "Connection '$CONNECTION_NAME' is not active."
    fi

    # Remove the connection entirely
    echo "Removing connection '$CONNECTION_NAME'..."
    nmcli connection delete "$CONNECTION_NAME"
    echo "Connection '$CONNECTION_NAME' has been removed."
else
    echo "Connection '$CONNECTION_NAME' does not exist. Nothing to disable or remove."
fi

echo "Access point has been disabled and removed."
killall sleep
