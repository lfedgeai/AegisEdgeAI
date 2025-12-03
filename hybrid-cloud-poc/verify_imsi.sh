#!/bin/bash

# --- Configuration ---
# Set the IMSI of the ONLY authorized SIM card.
# (Replace this with your confirmed IMSI: 214070610960475)
EXPECTED_IMSI="214070610960475"
# ---------------------

echo "Starting Robust SIM Card Verification..."

# 1. Dynamically find the path of the first recognized Huawei modem.
#    This searches for the vendor tag '[huawei]' to find any Huawei modem connected.
MODEM_PATH=$(sudo mmcli -L | grep '\[huawei\]' | head -n 1 | awk '{print $1}')

if [ -z "$MODEM_PATH" ]; then
    echo "FATAL ERROR: No Huawei modem found by ModemManager. Modem not plugged in or not ready."
    exit 1
fi

# 2. Extract the Modem/SIM Index from the path (e.g., extracting '5').
SIM_INDEX=$(echo "$MODEM_PATH" | rev | cut -d/ -f1 | rev)

# Find and display the actual model name for user confirmation
MODEM_MODEL=$(sudo mmcli -L | grep '\[huawei\]' | head -n 1 | awk '{print $3}')

echo "✅ Modem '$MODEM_MODEL' found at Index: $SIM_INDEX"

# 3. Check if the SIM object exists using the dynamic index
if ! sudo mmcli -i $SIM_INDEX &> /dev/null; then
    echo "ERROR: SIM object $SIM_INDEX not found."
    echo "The SIM card may be missing, locked, or unreadable."
    exit 1
fi

# 4. Extract the current IMSI using the correct grep/awk structure
CURRENT_IMSI=$(sudo mmcli -i $SIM_INDEX | grep 'imsi:' | awk '{print $3}')

# 5. Perform the validation check
if [ -z "$CURRENT_IMSI" ]; then
    # This happens if the SIM is physically present but ModemManager can't read the IMSI (e.g., failed access/locked)
    echo "ERROR: SIM card is present but the IMSI could not be read. Possible fault or lock."
    # Action: Lock down the modem
    # sudo mmcli -m $SIM_INDEX --disable
    exit 1
elif [ "$CURRENT_IMSI" != "$EXPECTED_IMSI" ]; then
    echo "🚨 SECURITY ALERT: UNKNOWN SIM CARD PLUGGED IN! 🚨"
    echo "Expected IMSI: $EXPECTED_IMSI (Authorized)"
    echo "Actual IMSI: $CURRENT_IMSI (Unauthorized)"
    # Action: Lock down the modem
    # sudo mmcli -m $SIM_INDEX --disable
    exit 1
else
    echo "✅ SUCCESS: Authorized SIM card detected."
    echo "IMSI: $CURRENT_IMSI matches the expected value."
    # Action: Proceed with connection
    # sudo mmcli -m $SIM_INDEX --simple-connect="apn=internet"
fi
