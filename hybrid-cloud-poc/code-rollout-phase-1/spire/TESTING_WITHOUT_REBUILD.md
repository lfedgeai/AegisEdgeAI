# Running Tests Without Rebuilding Binaries

This document describes options for running SPIRE tests without rebuilding the binaries, which is useful when binaries are already committed to git or you want to save build time.

## Options Overview

### Option 1: Use Environment Variables (Recommended)

Set environment variables to skip building:

```bash
# Skip building binaries
export SKIP_BUILD=1

# Skip building Docker images
export SKIP_IMAGE_BUILD=1

# Run unit tests (no binaries needed)
make test

# Run integration tests (requires Docker images, but won't rebuild binaries)
make integration
```

### Option 2: Use Conditional Build Targets

The Makefile now includes targets that only build if binaries/images don't exist:

```bash
# Build binaries only if they don't exist
make build-if-needed

# Build static binaries only if they don't exist
make build-static-if-needed

# Build Docker images only if they don't exist
make images-no-load-if-needed
```

### Option 3: Use Helper Functions in Test Scripts

The test integration framework includes helper functions:

```bash
# In test scripts, use ensure-images to check and build only if needed
ensure-images spire-server:latest-local spire-agent:latest-local

# Or check if images exist without building
if check-images spire-server:latest-local spire-agent:latest-local; then
    echo "Images exist"
fi
```

### Option 4: Pre-build Images Once

Build Docker images once and reuse them:

```bash
# Build images once
make images

# Later, run tests without rebuilding
SKIP_IMAGE_BUILD=1 make integration
```

## Detailed Usage

### Unit Tests

Unit tests don't require binaries, so they can always run without building:

```bash
make test
```

### Integration Tests

Integration tests require Docker images. Options:

**Option A: Use existing images (if already built)**
```bash
SKIP_IMAGE_BUILD=1 make integration
```

**Option B: Build images only if missing**
```bash
make images-no-load-if-needed
make integration
```

**Option C: Use ensure-images in test setup scripts**
```bash
# In a test suite's 00-setup script:
ensure-images spire-server:latest-local spire-agent:latest-local
```

### Building Static Binaries for Docker

If you have binaries in git but need static binaries for Docker:

```bash
# Skip regular build, but build static if needed
SKIP_BUILD=1 make build-static-if-needed
```

## Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `SKIP_BUILD` | Skip building binaries (`bin/spire-server`, `bin/spire-agent`) | Unset (build normally) |
| `SKIP_IMAGE_BUILD` | Skip building Docker images | Unset (build normally) |

## Makefile Targets Reference

| Target | Description |
|--------|-------------|
| `build` | Always build binaries |
| `build-if-needed` | Build binaries only if they don't exist (unless `SKIP_BUILD` is set) |
| `build-static` | Always build static binaries for Docker |
| `build-static-if-needed` | Build static binaries only if they don't exist (unless `SKIP_BUILD` is set) |
| `images` | Build Docker images and load them |
| `images-no-load` | Build Docker images (OCI archives) |
| `images-no-load-if-needed` | Build Docker images only if they don't exist locally |
| `test` | Run unit tests (no binaries needed) |
| `integration` | Run integration tests (requires Docker images) |

## Examples

### Example 1: Run tests with existing binaries and images

```bash
# Assume binaries and images already exist
SKIP_BUILD=1 SKIP_IMAGE_BUILD=1 make integration
```

### Example 2: Ensure images exist before running tests

```bash
# Build images only if missing
make images-no-load-if-needed

# Run tests
make integration
```

### Example 3: Run specific test suite without rebuilding

```bash
cd test/integration
SKIP_IMAGE_BUILD=1 ./test.sh suites/entries
```

### Example 4: Use in CI/CD pipeline

```bash
# Build images once
make images

# Run multiple test suites without rebuilding
SKIP_IMAGE_BUILD=1 make integration SUITES="suites/entries suites/k8s"
```

## Troubleshooting

### Issue: Tests fail with "image not found"

**Solution**: Build the images first:
```bash
make images
```

Or use the conditional build:
```bash
make images-no-load-if-needed
```

### Issue: Binaries are outdated

**Solution**: Force a rebuild:
```bash
unset SKIP_BUILD
make build
```

### Issue: Docker images are outdated

**Solution**: Force a rebuild:
```bash
unset SKIP_IMAGE_BUILD
make images
```

## Notes

- The `SKIP_BUILD` and `SKIP_IMAGE_BUILD` variables only affect the build process, not the test execution
- Unit tests (`make test`) never require binaries - they run Go tests directly
- Integration tests always require Docker images, but can use existing ones
- The `-if-needed` targets check for file/image existence, not timestamps (they won't rebuild outdated files)

