<!-- Version: 0.1.0 | Last Updated: 2025-12-29 -->
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Pillar 0 Governance**: Added LICENSE (Apache 2.0), CONTRIBUTING.md (with DCO), SECURITY.md, and CODE_OF_CONDUCT.md.
- **Project Infrastructure**: Implemented `.pre-commit-config.yaml` for standardized linting and formatting across Go, Rust, and Python.
- **CI/CD**: Added GitHub Actions workflow (`ci.yml`) for automated integration testing on PRs.
- **Documentation**: Consolidated prerequisites into `install_prerequisites.sh` and moved production gaps to the roadmap.

### Changed
- **Task 12b**: Implemented Sensor Schema Separation in SPIRE claims (unified mobile vs. GNSS).
- **Architecture Doc**: Converted stale absolute `file:///` URLs to relative repository paths.

### Fixed
- **Task 14b**: Fixed "Empty TPM response" bug in delegated certification flow.
- **Security**: Removed `InsecureSkipVerify` in distribution tools and hardened TLS validation.
- **Cleanup**: Removed hundreds of stale `.bak` and `.orig` configuration files.
