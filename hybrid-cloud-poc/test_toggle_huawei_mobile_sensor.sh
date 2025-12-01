#!/bin/bash

# Configuration for mwserver11
# Target: Huawei Modem on Bus 1, Port 12
DEVICE_PATH="/sys/bus/usb/devices/1-12"
ROOT_HUB_PATH="/sys/bus/usb/devices/usb1"

# Check for root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)."
  exit 1
fi

case "$1" in
    off)
        if [ -d "$DEVICE_PATH" ]; then
            echo "Removing Huawei modem (1-12) from kernel..."
            echo 1 > "$DEVICE_PATH/remove"
            echo "Done. Device should be gone from lsusb."
        else
            echo "Device 1-12 not found. It might already be removed."
        fi
        ;;
        
    on)
        echo "Rescanning Root Hub (Bus 1) to rediscover device..."
        echo "WARNING: This will briefly reset other devices on Bus 1 (including Tascam Hubs)."
        
        # De-authorize the whole bus to clear state
        echo 0 > "$ROOT_HUB_PATH/authorized"
        # Re-authorize to trigger full enumeration
        echo 1 > "$ROOT_HUB_PATH/authorized"
        
        echo "Scan complete. Waiting 2 seconds for initialization..."
        sleep 2
        
        if [ -d "$DEVICE_PATH" ]; then
            echo "Success: Huawei modem is back."
        else
            echo "Error: Device did not reappear. Physical replug might be required."
        fi
        ;;
        
    status)
        if [ -d "$DEVICE_PATH" ]; then
            echo "Status: ONLINE (Device 1-12 exists)"
            lsusb -s 1:12
        else
            echo "Status: OFFLINE (Device 1-12 not found in sysfs)"
        fi
        ;;
        
    *)
        echo "Usage: $0 {off|on|status}"
        exit 1
        ;;
esac
