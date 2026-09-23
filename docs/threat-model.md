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

## Identity separation

Keycloak authenticates humans through SSO and MFA. OpenBao authorizes machine
and deployment actions and issues short-lived SSH credentials. Personal TOTP
and WebAuthn credentials remain inside Keycloak and never enter Jenkins or
OpenBao. A shared service account, machine-readable TOTP, or reusable SSH key
must not substitute for an attributable human approval. See
[ADR-0008](adr/0008-separate-human-approval-from-machine-credentials.md).

## Deferred analysis

Detailed data-flow diagrams, abuse cases, Kubernetes workload threats, cloud IAM
policies, and incident exercises are added with their implementation phases.
