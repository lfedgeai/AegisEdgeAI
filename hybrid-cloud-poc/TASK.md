# Task: Analyze Hybrid Cloud POC

- [x] Locate `hybrid-cloud-poc` directory (Found at: `/home/mw/AegisSovereignAI/hybrid-cloud-poc/`) <!-- id: 0 -->
- [x] Read `README.md` and `README-arch-sovereign-unified-identity.md` <!-- id: 1 -->
- [x] Analyze codebase for "unified identity feature flag" usage <!-- id: 2 -->
- [x] Evaluate code quality <!-- id: 3 -->
- [x] Assess production readiness requirements <!-- id: 4 -->
- [x] Analyze "Unified Identity" context from AegisSovereignAI repo story <!-- id: 5 -->
- [x] Review AegisSovereignAI GitHub issues for alignment with analysis <!-- id: 6 -->
- [x] Compare implementation with upstream SPIRE/Keylime (Feature Flag correctness) <!-- id: 7 -->
- [x] Validate all modifications are under feature flag (Gap Analysis) <!-- id: 10 -->
- [x] Update `analysis_report.md` with new findings <!-- id: 8 -->
- [x] Commit report to git <!-- id: 9 -->
- [x] Analyze Keylime components for custom modifications <!-- id: 11 -->
- [x] Define refactoring strategy (SPIRE Core -> Plugin) <!-- id: 12 -->
- [x] Create `upstream_merge_roadmap.md` <!-- id: 13 -->

# Execution Phase

## Pillar 1: Test Infrastructure (Safety Net)
- [ ] Create/Harden `test_integration.sh` (Fail-fast, structured logging) <!-- id: 20 -->
- [ ] Set up clean error reporting for CI/Watcher <!-- id: 21 -->

## Pillar 2: Upstreaming Implementation (Refactoring)
- [ ] **Task 1**: Keylime Agent - Delegated Certifier Endpoint <!-- id: 14 -->
- [ ] **Task 2**: Keylime Agent - Attested Geolocation API <!-- id: 15 -->
- [ ] **Task 3**: Keylime Verifier - Add Verification API & Cleanup <!-- id: 16 -->
- [ ] **Task 4**: SPIRE Server - Validator Plugin (`spire-plugin-unified-identity`) <!-- id: 17 -->
- [ ] **Task 5**: SPIRE Agent - Collector Plugin (`spire-plugin-unified-identity`) <!-- id: 18 -->
- [ ] **Task 6**: SPIRE Creds - Credential Composer <!-- id: 19 -->

## Pillar 3: Production Readiness (Hardening)
- [ ] Address Keylime Client TLS (`InsecureSkipVerify`) <!-- id: 22 -->
- [ ] Secure Secrets Management (CAMARA API Keys) <!-- id: 23 -->
- [ ] Resolve AegisSovereignAI GitHub Issues <!-- id: 24 -->
