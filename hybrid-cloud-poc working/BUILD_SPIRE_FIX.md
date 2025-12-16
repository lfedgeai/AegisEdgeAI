# Fix SPIRE Build Issues

## Problem
The SPIRE build is failing because required files are missing:
- `.go-version`
- `.spire-tool-versions`
- Git repository metadata

## Solution: Use System Go Instead of Makefile's Go Installer

### Option 1: Build with System Go (Recommended)

```bash
cd ~/dhanush/hybrid-cloud-poc-backup/spire

# Check if Go is installed
go version
# Should show: go version go1.21.x or go1.22.x

# If Go is not installed, install it:
# sudo apt update
# sudo apt install golang-go

# Build SPIRE Agent directly with Go
cd cmd/spire-agent
go build -o ../../bin/spire-agent
cd ../..

# Build SPIRE Server directly with Go
cd cmd/spire-server
go build -o ../../bin/spire-server
cd ../..

# Verify builds
ls -lh bin/spire-agent bin/spire-server
```

### Option 2: Create Missing Files

If you want to use `make build`, create the missing files:

```bash
cd ~/dhanush/hybrid-cloud-poc-backup/spire

# Create .go-version file
echo "1.21.5" > .go-version

# Create .spire-tool-versions file
cat > .spire-tool-versions << 'EOF'
GOLANG_VERSION=1.21.5
PROTOBUF_VERSION=3.20.3
GOLANGCI_LINT_VERSION=1.54.2
EOF

# Initialize git repository (optional, just to avoid errors)
git init
git config user.email "you@example.com"
git config user.name "Your Name"
git add .
git commit -m "Initial commit"

# Now try make build
make build
```

### Option 3: Simple Direct Build (Fastest)

```bash
cd ~/dhanush/hybrid-cloud-poc-backup/spire

# Create bin directory
mkdir -p bin

# Build agent
go build -o bin/spire-agent ./cmd/spire-agent

# Build server
go build -o bin/spire-server ./cmd/spire-server

# Verify
ls -lh bin/
```

---

## After Building

### Verify the Build

```bash
# Check if binaries exist
ls -lh ~/dhanush/hybrid-cloud-poc-backup/spire/bin/spire-agent
ls -lh ~/dhanush/hybrid-cloud-poc-backup/spire/bin/spire-server

# Test agent
~/dhanush/hybrid-cloud-poc-backup/spire/bin/spire-agent --version

# Test server
~/dhanush/hybrid-cloud-poc-backup/spire/bin/spire-server --version
```

### Update Test Scripts to Use New Binaries

Your test scripts might be looking for SPIRE binaries in a different location. Check:

```bash
# Find where test scripts expect SPIRE binaries
grep -n "spire-agent" ~/dhanush/hybrid-cloud-poc-backup/test_complete.sh | head -5
grep -n "spire-server" ~/dhanush/hybrid-cloud-poc-backup/test_complete_control_plane.sh | head -5
```

If they're looking in the wrong place, you might need to:

1. Copy binaries to expected location, OR
2. Update the scripts to point to `spire/bin/`

---

## Quick Test

After building, test the changes:

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Clean up
pkill keylime_agent spire-agent keylime-verifier keylime-registrar spire-server tpm2-abrmd 2>/dev/null || true
rm -rf /tmp/keylime-agent /tmp/spire-* /opt/spire/data/* keylime/cv_ca keylime/*.db

# Start control plane
./test_complete_control_plane.sh --no-pause

# Wait
sleep 10

# Start agent
./test_complete.sh --no-pause

# Check logs
tail -50 /tmp/spire-agent.log | grep -i "quote"
```

---

## Troubleshooting

### Error: "go: command not found"

Install Go:
```bash
sudo apt update
sudo apt install golang-go
go version
```

### Error: "package X is not in GOROOT"

Set GOPATH:
```bash
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
go build -o bin/spire-agent ./cmd/spire-agent
```

### Error: "cannot find package"

Install dependencies:
```bash
cd ~/dhanush/hybrid-cloud-poc-backup/spire
go mod download
go mod tidy
go build -o bin/spire-agent ./cmd/spire-agent
```

---

## Recommended Approach

**Use Option 3 (Simple Direct Build)** - it's the fastest and most reliable:

```bash
cd ~/dhanush/hybrid-cloud-poc-backup/spire
mkdir -p bin
go build -o bin/spire-agent ./cmd/spire-agent
go build -o bin/spire-server ./cmd/spire-server
ls -lh bin/
```

This should work even without the missing files.
