# Export the public key in PEM format from a TPM key context
# Replace KEY_CTX with your actual key context (private/public)
KEY_CTX="app.ctx"
PUB_PEM="appsk_pubkey.pem"

# Extract public part and convert to PEM (done on device with TPM)
tpm2_readpublic -c "$KEY_CTX" -f pem -o "$PUB_PEM"
echo "[INFO] Exported TPM public key to $PUB_PEM"

