# Contributing to Aegis Sovereign Unified Identity

Thank you for your interest in contributing to the Aegis Sovereign Unified Identity project! We welcome contributions from the community.

## Developer Certificate of Origin (DCO)

All contributions to this project must include a "Signed-off-by" line in every commit message. This indicates that you agree to the terms of the Developer Certificate of Origin (DCO), a legal statement that you have the right to submit the contribution.

Example commit message:
```
Add nested SVID claim deduplication logic

Signed-off-by: Your Name <your.email@example.com>
```

You can automate this by using the `-s` flag with `git commit`.

## Contribution Process

1. **Find or Create an Issue:** Before starting work, please check the existing issues or create a new one to discuss your proposed changes.
2. **Fork the Repository:** Create a fork of the repository and clone it to your local machine.
3. **Commit Changes:** Implement your changes in a new branch. Ensure all commits are signed-off.
4. **Run Tests:** Verify your changes using the provided integration tests (`test_integration.sh`).
5. **Submit a Pull Request:** Open a pull request against the `main` branch. Provide a clear description of the changes.

## Code Style

- **Python:** Follow PEP 8 guidelines.
- **Go:** Follow standard Go formatting (`go fmt`).
- **Rust:** Follow standard Rust formatting (`cargo fmt`).

## Code of Conduct

All contributors are expected to adhere to our [Code of Conduct](CODE_OF_CONDUCT.md).
