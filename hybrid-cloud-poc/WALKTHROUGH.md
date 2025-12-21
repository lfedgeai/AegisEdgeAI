# Walkthrough: Unified Identity Analysis & Roadmap

## Overview
We have completed a comprehensive analysis of the "Sovereign Hybrid Cloud Unified Identity" feature and established a concrete roadmap for merging it upstream. This feature binds workload identity to hardware-rooted integrity (TPM) and physical location (GPS/Cellular).

## Key Findings (Analysis Phase)
*   **Feature Flag**: The `FlagUnifiedIdentity` correctly gates the custom logic in SPIRE Core.
*   **Gap Analysis**:
    *   **Logic**: Core orchestration logic in `agent.go` and `service.go` is complex and invasive.
    *   **Protocol**: Keylime Agent protocol was modified to include `geolocation` in quotes.
    *   **Verification**: Keylime Verifier was patched to handle this extra data.
*   **Readiness**: The PoC works but uses "Fork & Patch" architecture, which is not sustainable for upstreaming.

## The Plan (Roadmap Phase)
We developed a **6-Task Roadmap** to refactor this architecture into standard Upstream Contributions.

| Component | Task | Strategy |
| :--- | :--- | :--- |
| **Keylime Agent** | 1. `delegated_certifier` endpoint | Core Feature Request |
| **Keylime Agent** | 2. `extended_metadata` protocol | Core Feature Request |
| **Keylime Verifier** | 3. `verify_external_facts` API | Generic API Endpoint |
| **SPIRE Server** | 4. `spire-plugin-unified-identity` | Custom Plugin (Validator) |
| **SPIRE Agent** | 5. `spire-plugin-unified-identity` | Custom Plugin (Collector) |
| **SPIRE Creds** | 6. `CredentialComposer` config | Standard Configuration |

## Next Steps
You are now ready to begin execution.
*   **Hand off** the Keylime tasks (1 & 2) to the Rust team.
*   **Hand off** the Keylime Verifier task (3) to the Python team.
*   **Begin** the SPIRE Go plugin development (Tasks 4 & 5).
