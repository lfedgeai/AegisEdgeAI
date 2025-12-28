# Contributing to AegisSovereignAI

Thank you for your interest in contributing to AegisSovereignAI! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Contributions](#making-contributions)
- [Code Style Guidelines](#code-style-guidelines)
- [Testing Requirements](#testing-requirements)
- [Pull Request Process](#pull-request-process)
- [Developer Certificate of Origin](#developer-certificate-of-origin)

## Code of Conduct

This project follows the [LF Projects Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## Getting Started

### Prerequisites

- **Go**: 1.22.0 or later
- **Rust**: 1.75.0 or later (with `wasm32-unknown-unknown` target)
- **Python**: 3.10 or later
- **TPM 2.0**: Hardware TPM or software TPM (swtpm) for testing

### Repository Structure

```
AegisSovereignAI/
├── hybrid-cloud-poc/          # Main PoC implementation
│   ├── spire/                 # SPIRE plugins and configurations
│   ├── keylime/               # Keylime verifier extensions (Python)
│   ├── rust-keylime/          # Keylime agent extensions (Rust)
│   ├── tpm-plugin/            # TPM Plugin Server
│   ├── enterprise-private-cloud/
│   │   └── wasm-plugin/       # Envoy WASM filter (Rust)
│   └── mobile-sensor-microservice/  # CAMARA API wrapper
├── compliance_agent/          # Compliance as Code agent
├── proposals/                 # Design proposals
└── zero-trust/                # Edge AI architecture
```

## Development Setup

### 1. Clone the Repository

```bash
git clone https://github.com/lfedgeai/AegisSovereignAI.git
cd AegisSovereignAI
```

### 2. Install Dependencies

```bash
# Go dependencies
cd hybrid-cloud-poc/spire
go mod download

# Rust dependencies
cd ../rust-keylime
cargo fetch

# Python dependencies
cd ../keylime
pip install -r requirements.txt

# WASM build target
rustup target add wasm32-unknown-unknown
```

### 3. Run Tests

```bash
cd hybrid-cloud-poc
./ci_test_runner.py --no-color
```

## Making Contributions

### Types of Contributions

We welcome the following types of contributions:

1. **Bug fixes**: Fix issues in existing code
2. **Features**: Add new functionality (discuss in an issue first)
3. **Documentation**: Improve or add documentation
4. **Tests**: Add or improve test coverage
5. **Upstream PRs**: Help prepare code for upstream SPIRE/Keylime

### Before You Start

1. **Check existing issues**: Look for related issues or discussions
2. **Open an issue**: For significant changes, discuss your approach first
3. **Fork the repository**: Create your own fork to work in

## Code Style Guidelines

### Go (SPIRE plugins)

- Follow [Effective Go](https://golang.org/doc/effective_go)
- Use `gofmt` and `golangci-lint`
- Match SPIRE's existing code style for plugin code

```bash
# Format and lint
gofmt -w .
golangci-lint run
```

### Rust (Keylime agent, WASM plugin)

- Follow [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
- Use `rustfmt` and `clippy`

```bash
# Format and lint
cargo fmt
cargo clippy -- -D warnings
```

### Python (Keylime verifier, microservices)

- Follow [PEP 8](https://pep8.org/)
- Use `ruff` or `black` for formatting
- Use type hints where possible

```bash
# Format and lint
ruff check --fix .
ruff format .
```

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(spire): add geolocation claims to credential composer
fix(keylime): handle empty TPM quote response
docs(readme): update installation instructions
```

## Testing Requirements

### Before Submitting a PR

1. **All existing tests pass**: Run the full test suite
2. **New tests for new code**: Add tests for new functionality
3. **No linter errors**: Fix all linting issues

### Running Tests

```bash
# Full integration test (requires TPM)
cd hybrid-cloud-poc
./ci_test_runner.py --no-color

# Unit tests by component
cd spire && go test ./...
cd rust-keylime && cargo test
cd keylime && python -m pytest
```

## Pull Request Process

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Your Changes

- Keep commits focused and atomic
- Write clear commit messages
- Update documentation as needed

### 3. Push and Create PR

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub.

### 4. PR Requirements

Your PR must:

- [ ] Pass all CI checks
- [ ] Have no merge conflicts
- [ ] Include DCO sign-off on all commits
- [ ] Have a clear description of changes
- [ ] Reference related issues (if any)
- [ ] Include tests for new functionality
- [ ] Update documentation if needed

### 5. Review Process

- At least one maintainer approval required
- Address review feedback promptly
- Keep the PR up to date with the target branch

## Developer Certificate of Origin

This project uses the [Developer Certificate of Origin (DCO)](https://developercertificate.org/) to ensure contributors have the right to submit their code.

### Signing Your Commits

Add a sign-off to your commit messages:

```bash
git commit -s -m "feat: add new feature"
```

This adds a line to your commit message:

```
Signed-off-by: Your Name <your.email@example.com>
```

### DCO Text

By signing off, you certify the following:

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

## Questions?

- Open a [GitHub Discussion](https://github.com/lfedgeai/AegisSovereignAI/discussions)
- Check existing [Issues](https://github.com/lfedgeai/AegisSovereignAI/issues)

Thank you for contributing to AegisSovereignAI!

