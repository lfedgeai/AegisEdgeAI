#!/bin/bash
set -euo pipefail

# Input secret data to be sealed
SECRET="my secret"
SEAL_INPUT_FILE="seal.dat"
PRIMARY_CTX="primary.ctx"
SEAL_PUB="seal.pub"
SEAL_PRIV="seal.priv"
SEAL_CTX="seal.ctx"
UNSEALED_OUTPUT="unsealed.dat"

# Create data to seal
echo "$SECRET" > "$SEAL_INPUT_FILE"

# 1. Create a Primary Key Context
tpm2_createprimary -C o -c "$PRIMARY_CTX"

# 2. Seal the data into the TPM
tpm2_create -C "$PRIMARY_CTX" -i "$SEAL_INPUT_FILE" -u "$SEAL_PUB" -r "$SEAL_PRIV"

# 3. Load the sealed object
tpm2_load -C "$PRIMARY_CTX" -u "$SEAL_PUB" -r "$SEAL_PRIV" -c "$SEAL_CTX"

# 4. Unseal the data from the transient object context
tpm2_unseal -c "$SEAL_CTX" > "$UNSEALED_OUTPUT"

# 5. Show the unsealed data
echo "Unsealed data:"
cat "$UNSEALED_OUTPUT"

