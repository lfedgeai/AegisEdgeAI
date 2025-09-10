# Vars
export SWTPM_DIR="$HOME/.swtpm/ztpm"
export SWTPM_PORT=2321
export SWTPM_CTRL=2322

# Kill old swtpm
pkill -f swtpm || true
rm -rf "$SWTPM_DIR"
mkdir -p "$SWTPM_DIR"

# Start swtpm on TCP
swtpm socket --tpm2 \
  --server type=tcp,port=$SWTPM_PORT \
  --ctrl   type=tcp,port=$SWTPM_CTRL \
  --tpmstate dir=$SWTPM_DIR \
  --flags not-need-init &

# Tell tpm2-tools to use it
export PREFIX="/opt/homebrew"
if [[ "$(uname)" == "Darwin" ]]; then
  export TPM2TOOLS_TCTI="libtss2-tcti-swtpm.dylib:host=127.0.0.1,port=${SWTPM_PORT}"
  export DYLD_LIBRARY_PATH="${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
else
  export TPM2TOOLS_TCTI="${TPM2TOOLS_TCTI:-swtpm:host=127.0.0.1,port=${SWTPM_PORT}}"
fi

# Initialise and test
sleep 1
tpm2 startup -c
tpm2 getcap properties-fixed
