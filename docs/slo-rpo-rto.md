# Service Objectives and Recovery Classes

Status: initial classification. Values are design targets until a later test
produces timestamped evidence.

## Classes

| Class | Example capability | Availability/SLO approach | Draft RPO | Draft RTO |
| --- | --- | --- | --- | --- |
| C0 | Git repository and operator trust kit | Recoverable source of truth | 24 hours | 4 hours |
| C1 | DNS, identity, Vault/OpenBao | Error-budgeted control plane | 15 minutes | 1 hour |
| C2 | Jenkins, GitOps, artifact services | Delivery may pause safely | 4 hours | 8 hours |
| C3 | Sample workloads and demonstrations | Best effort | 24 hours | 24 hours |
| C4 | Ephemeral test infrastructure | No continuity promise | None | Recreate |

## Measurement rules

- SLO indicators must be observable from the user's perspective where possible.
- Planned maintenance is reported, not silently removed from evidence.
- RPO is measured from restored data, not backup schedule configuration.
- RTO starts at declared incident time and ends only after validation passes.
- A class assignment must list dependencies whose weaker objective limits it.

Initial numbers are deliberately conservative and must be revised after restore
and game-day measurements. No Phase 0 document claims that a target is met.
