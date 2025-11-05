# Quick Reference: Running Tests Without Rebuilding

## Quick Start

### Run unit tests (no binaries needed)
```bash
make test
```

### Run integration tests with existing images
```bash
SKIP_IMAGE_BUILD=1 make integration
```

### Build images only if missing, then run tests
```bash
make images-no-load-if-needed
make integration
```

## Environment Variables

```bash
SKIP_BUILD=1          # Skip building binaries
SKIP_IMAGE_BUILD=1   # Skip building Docker images
```

## Common Workflows

### Workflow 1: Use existing binaries and images
```bash
SKIP_BUILD=1 SKIP_IMAGE_BUILD=1 make integration
```

### Workflow 2: Build only what's missing
```bash
make build-if-needed
make images-no-load-if-needed
make integration
```

### Workflow 3: Run specific test suite
```bash
cd test/integration
SKIP_IMAGE_BUILD=1 ./test.sh suites/entries
```

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make test` | Run unit tests (no build needed) |
| `make build-if-needed` | Build only if binaries missing |
| `make images-no-load-if-needed` | Build images only if missing |
| `make integration` | Run integration tests |

For more details, see `TESTING_WITHOUT_REBUILD.md`.

