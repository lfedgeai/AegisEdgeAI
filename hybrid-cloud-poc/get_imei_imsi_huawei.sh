#!/bin/bash

# ==============================================================================
# Script: get_imei_imsi_huawei_v2.sh
# Purpose: Robustly retrieve IMEI and IMSI by handling mmcli output formatting
# ==============================================================================

echo "--- Mobile Device Identity Retrieval ---"

# 1. Dynamically find the Huawei Modem
#    Matches any device with manufacturer '[huawei]'
MODEM_PATH=$(sudo mmcli -L | grep '\[huawei\]' | head -n 1 | awk '{print $1}')

if [ -z "$MODEM_PATH" ]; then
    echo "❌ ERROR: No Huawei modem detected."
    exit 1
fi

# Extract the Modem Index number (e.g., '5' from '.../Modem/5')
MODEM_INDEX=$(echo "$MODEM_PATH" | rev | cut -d/ -f1 | rev)
echo "✅ Modem detected at Index: $MODEM_INDEX"

# 2. Get the IMEI (Hardware Identity)
#    Logic: Find line containing "equipment id", assume structure "...: VALUE", grab everything after colon
IMEI=$(sudo mmcli -m "$MODEM_INDEX" | grep 'equipment id' | awk -F': ' '{print $2}' | awk '{print $1}')

if [ -z "$IMEI" ]; then
    echo "⚠️  WARNING: Could not retrieve IMEI."
    IMEI="Unknown"
else
    echo "   --> IMEI (Hardware ID): $IMEI"
fi

# 3. Find the SIM Object Path
#    Logic: Find line containing "primary sim path", grab everything after colon
SIM_PATH=$(sudo mmcli -m "$MODEM_INDEX" | grep 'primary sim path' | awk -F': ' '{print $2}' | awk '{print $1}')

# 4. Get the IMSI (Subscriber Identity)
if [ -z "$SIM_PATH" ] || [ "$SIM_PATH" == "--" ]; then
    echo "❌ ERROR: No SIM card detected in the modem."
    IMSI="Missing"
else
    # Extract the SIM Index from the path (e.g., '5' from '.../SIM/5')
    SIM_INDEX=$(echo "$SIM_PATH" | rev | cut -d/ -f1 | rev)
    
    # Query the SIM object for the IMSI
    # Logic: Find line containing "imsi:", grab everything after colon
    IMSI=$(sudo mmcli -i "$SIM_INDEX" | grep 'imsi' | awk -F': ' '{print $2}' | awk '{print $1}')
    
    if [ -z "$IMSI" ]; then
        echo "⚠️  WARNING: SIM detected but IMSI not readable (SIM might be locked/PIN required)."
        IMSI="Locked/Unreadable"
    else
        echo "   --> IMSI (Subscriber ID): $IMSI"
    fi
fi

echo "----------------------------------------"
echo "Device Summary:"
echo "Modem IMEI: $IMEI"
echo "SIM IMSI:   $IMSI"
echo "----------------------------------------"
