#!/bin/bash

echo "Starting Dynamic IMSI Retrieval (Searching for any Huawei Modem)..."

# 1. Dynamically find the path of the first recognized Huawei modem.
#    The use of brackets '\[huawei\]' ensures it matches the exact string, not just the word 'huawei'.
MODEM_PATH=$(sudo mmcli -L | grep '\[huawei\]' | head -n 1 | awk '{print $1}')

if [ -z "$MODEM_PATH" ]; then
    echo "ERROR: No Huawei modem found by ModemManager."
    echo "Please ensure the modem is plugged in and recognized by 'mmcli -L'."
    exit 1
fi

# 2. Extract the Modem/SIM Index from the path.
SIM_INDEX=$(echo "$MODEM_PATH" | rev | cut -d/ -f1 | rev)

# Find and display the actual model name for user confirmation
MODEM_MODEL=$(sudo mmcli -L | grep '\[huawei\]' | head -n 1 | awk '{print $3}')

echo "✅ Modem '$MODEM_MODEL' found at Index: $SIM_INDEX"

# 3. Check if the SIM object exists
if ! sudo mmcli -i $SIM_INDEX &> /dev/null; then
    echo "ERROR: SIM object $SIM_INDEX not found or inaccessible."
    echo "The SIM card may be missing, locked, or unreadable."
    exit 1
fi

# 4. Extract the IMSI
IMSI_VALUE=$(sudo mmcli -i $SIM_INDEX | grep 'imsi:' | awk '{print $3}')

# 5. Output the final result
if [ -z "$IMSI_VALUE" ]; then
    echo "ERROR: SIM card is present but the IMSI field is empty."
    exit 1
else
    echo "--- Retrieval Successful ---"
    echo "IMSI: $IMSI_VALUE"
    echo "--------------------------"
fi
