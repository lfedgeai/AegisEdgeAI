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

# Tell tpm2-tools to use it - detect architecture and OS
ARCH=$(uname -m)
OS=$(uname -s)

case "$OS" in
  Darwin)
    # macOS (both Intel and Apple Silicon)
    export PREFIX="/opt/homebrew"
    export TPM2TOOLS_TCTI="libtss2-tcti-swtpm.dylib:host=127.0.0.1,port=${SWTPM_PORT}"
    export DYLD_LIBRARY_PATH="${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
    echo "[INFO] macOS detected - using Homebrew prefix"
    ;;
  Linux)
    # Linux - handle ARM64 vs x86_64
    case "$ARCH" in
      aarch64|arm64)
        # ARM64 Linux - may have custom installation
        if [ -f "/usr/local/bin/swtpm" ]; then
          export PREFIX="/usr/local"
          export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
          export PATH="${PREFIX}/bin:${PATH}"
          echo "[INFO] ARM64 Linux detected - using custom compiled TPM stack"
        else
          export PREFIX="/usr"
          echo "[INFO] ARM64 Linux detected - using system packages"
        fi
        ;;
      *)
        # x86_64 and other architectures
        export PREFIX="/usr"
        echo "[INFO] Linux x86_64 detected - using system packages"
        ;;
    esac
    export TPM2TOOLS_TCTI="${TPM2TOOLS_TCTI:-swtpm:host=127.0.0.1,port=${SWTPM_PORT}}"
    ;;
  *)
    echo "[WARN] Unknown OS: $OS - using default configuration"
    export PREFIX="/usr"
    export TPM2TOOLS_TCTI="${TPM2TOOLS_TCTI:-swtpm:host=127.0.0.1,port=${SWTPM_PORT}}"
    ;;
esac

echo "[INFO] Using TPM2TOOLS_TCTI=$TPM2TOOLS_TCTI"
echo "[INFO] Using PREFIX=$PREFIX"

# Initialise and test
sleep 1
tpm2 startup -c
tpm2 getcap properties-fixed
