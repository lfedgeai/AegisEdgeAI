# Build Instructions for Phase 1 Implementation

## Overview

This document provides step-by-step instructions for building and testing the Phase 1 implementation of the Unified Identity feature.

## Prerequisites

1. **Go 1.24.6 or later** - Check with `go version`
2. **Protocol Buffer Compiler (protoc)** - Version 30.2 or later
3. **unzip utility** - Required for downloading protoc
4. **Make** - For running build scripts

## Step 1: Install Dependencies

### Install protoc (if not already installed)

On Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y unzip
# Download and install protoc
PROTOC_VERSION=30.2
curl -LO "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip"
unzip protoc-${PROTOC_VERSION}-linux-x86_64.zip -d /tmp/protoc
sudo mv /tmp/protoc/bin/protoc /usr/local/bin/
sudo mv /tmp/protoc/include/* /usr/local/include/
```

On macOS:
```bash
brew install protobuf
```

## Step 2: Regenerate Protobuf Code

The proto files have been modified, so you must regenerate the Go code:

### Regenerate go-spiffe protobufs

```bash
cd hybrid-cloud-poc/code-rollout-phase-1/go-spiffe
make generate
```

This will:
- Download the required protoc version (if not already present)
- Download protoc-gen-go and protoc-gen-go-grpc
- Regenerate `proto/spiffe/workload/workload.pb.go`
- Regenerate `proto/spiffe/workload/workload_grpc.pb.go`

### Regenerate spire-api-sdk protobufs

```bash
cd hybrid-cloud-poc/code-rollout-phase-1/spire-api-sdk
make generate
```

This will regenerate `proto/spire/api/server/svid/v1/svid.pb.go` and related files.

## Step 3: Build SPIRE

```bash
cd hybrid-cloud-poc/code-rollout-phase-1/spire
go build ./cmd/spire-server
go build ./cmd/spire-agent
```

## Step 4: Verify Build

Check that the binaries were created:

```bash
ls -lh spire-server spire-agent
```

## Step 5: Run Tests

### Run unit tests for new functionality

```bash
cd hybrid-cloud-poc/code-rollout-phase-1/spire

# Test Keylime client
go test ./pkg/server/sovereign/keylime/... -v

# Test policy evaluation
go test ./pkg/server/sovereign/... -v

# Test agent sovereign handling
go test ./pkg/agent/endpoints/workload/... -run TestSovereign -v
```

### Run all tests (to ensure backward compatibility)

```bash
cd hybrid-cloud-poc/code-rollout-phase-1/spire
go test ./pkg/... -run TestSovereign -v
```

## Step 6: Enable Feature Flag (Optional)

To test with the feature flag enabled, add to your SPIRE configuration:

**server.conf**:
```hcl
server {
    # ... other config ...
    feature_flags = ["Unified-Identity"]
}
```

**agent.conf**:
```hcl
agent {
    # ... other config ...
    feature_flags = ["Unified-Identity"]
}
```

## Troubleshooting

### Error: "undefined: workload.SovereignAttestation"

**Solution**: The protobuf code hasn't been regenerated. Run `make generate` in the appropriate directory.

### Error: "protoc: not found"

**Solution**: Install protoc as described in Step 1.

### Error: "unzip: not found"

**Solution**: Install unzip:
```bash
sudo apt-get install unzip  # Ubuntu/Debian
brew install unzip          # macOS
```

### Error: "make: command not found"

**Solution**: Install make:
```bash
sudo apt-get install build-essential  # Ubuntu/Debian
xcode-select --install                # macOS
```

## Verification Checklist

- [ ] Protobuf code regenerated successfully
- [ ] SPIRE server builds without errors
- [ ] SPIRE agent builds without errors
- [ ] All new unit tests pass
- [ ] Feature flag works (disabled by default)
- [ ] No compilation errors

## Next Steps

Once the build is successful, you can:
1. Test the feature with the feature flag enabled
2. Run integration tests
3. Review logs to verify sovereign attestation flow
4. Proceed to Phase 2 implementation

