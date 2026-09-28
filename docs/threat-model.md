# Initial Threat Model

Status: active baseline; updated for the Phase 2 trust boundaries.

## Assets

- source history and release provenance;
- DNS and domain ownership;
- identity, MFA, TOTP, and YubiKey enrollment data;
- OpenBao recovery and bootstrap material;
- CI/CD approval authority and short-lived deployment credentials;
- infrastructure state, backups, artifacts, and observability data;
- cloud accounts and the ability to create billable resources.

## Trust boundaries

The primary boundaries are the developer workstation, Git hosting, CI runners,
external DNS/registrar accounts, the Incus network, the workload cluster,
identity/secrets services, backup storage, and each cloud account or tenant.

## Priority threats and controls

| Threat | Initial controls |
| --- | --- |
| Stolen maintainer account | Phishing-resistant MFA/YubiKey, signed human commits, protected branch, recovery procedure |
| Secret committed to Git | Ignore rules, Gitleaks locally and in CI, immediate rotation procedure |
| Pipeline impersonation or replay | Keycloak human identity and MFA, artifact-bound single-use approval, short-lived OpenBao SSH certificates |
| Compromised workload cluster controls recovery | Keep core identity, secret, delivery, and backup control services outside that cluster |
| DNS takeover | Registrar lock, MFA, DNSSEC, scoped DNS token, tested account recovery |
| Supply-chain substitution | Exact versions, pinned actions, checksums/signatures, dependency review |
| Destructive or costly automation | Plan-first workflow, explicit environment confirmation, TTL/budget labels, least-privilege credentials |
| Backup exists but cannot restore | Separate failure domain and scheduled restore validation with evidence |
| Compromised secrets-service bootstrap | Signed package provenance, trusted-host access, encrypted Shamir outputs, short-lived bootstrap credentials, and explicit initial-root-token retirement |
| Compromised online intermediate | Offline root separation, bounded intermediate and leaf lifetimes, revocation endpoints, and a documented replacement ceremony |
| Lost seal material | One PGP-encrypted share and its passphrase-protected recovery key in independently recoverable encrypted backups; no plaintext share enters Git, disk, logs, or evidence. This single-operator profile does not claim quorum. |
| Audit loss or bypass | Declarative file audit enabled before routine use, protected local storage, rotation checks, and validation that requests fail when every audit device is unavailable |

## Identity separation

Keycloak authenticates humans through SSO and MFA. OpenBao authorizes machine
and deployment actions and issues short-lived SSH credentials. Personal TOTP
and WebAuthn credentials remain inside Keycloak and never enter Jenkins or
OpenBao. A shared service account, machine-readable TOTP, or reusable SSH key
must not substitute for an attributable human approval. See
[ADR-0008](adr/0008-separate-human-approval-from-machine-credentials.md).

## Phase 2 secrets bootstrap boundary

The signed repository and verified OpenBao package may create an empty, sealed
service, but they cannot produce their own external trust. A human operator
supplies a bootstrap listener certificate from the operator-root workflow,
initializes OpenBao with a PGP-encrypted Shamir output, and presents the 1-of-1
share only through the guarded unseal stream. The initial root token exists only
long enough to install scoped policy and a bounded bootstrap administrator.

OpenBao generates the online intermediate private key internally and exports
only a CSR. The offline root signs that CSR outside the platform. A compromise
of the running service can therefore issue within the intermediate's policy and
lifetime, but cannot recover the offline root. Recovery starts with trusted
host access and the external Shamir share, restores a verified Raft snapshot
only into an isolated instance, and reconnects DNS or consumers only after
validation. Detailed custody and redaction rules are in the
[OpenBao foundation runbook](runbooks/openbao-foundation.md).

The 1-of-1 seal is a deliberate single-operator reference-lab tradeoff. It
avoids pretending that multiple files held by the same person are independent
custodians, but it makes loss or compromise of that custody material decisive.
Any production or genuinely multi-operator profile must rekey to independently
held threshold shares and test that separate ceremony first.

## Deferred analysis

Detailed data-flow diagrams, abuse cases, Kubernetes workload threats, cloud IAM
policies, and incident exercises are added with their implementation phases.
