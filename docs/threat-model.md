# Initial Threat Model

Status: Phase 0 baseline; revisit at every new trust boundary.

## Assets

- source history and release provenance;
- DNS and domain ownership;
- identity, MFA, TOTP, and YubiKey enrollment data;
- Vault/OpenBao recovery and bootstrap material;
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
| Pipeline impersonation or replay | Keycloak human identity, explicit approval, Vault/OpenBao TOTP validation, short-lived SSH certificates |
| Compromised workload cluster controls recovery | Keep core identity, secret, delivery, and backup control services outside that cluster |
| DNS takeover | Registrar lock, MFA, DNSSEC, scoped DNS token, tested account recovery |
| Supply-chain substitution | Exact versions, pinned actions, checksums/signatures, dependency review |
| Destructive or costly automation | Plan-first workflow, explicit environment confirmation, TTL/budget labels, least-privilege credentials |
| Backup exists but cannot restore | Separate failure domain and scheduled restore validation with evidence |

## Identity separation

Keycloak authenticates humans through SSO and MFA. Vault/OpenBao authorizes
machine and deployment actions, validates pipeline TOTP when required, and
issues short-lived SSH credentials. A shared service account and reusable SSH
key must not substitute for an attributable human approval.

## Deferred analysis

Detailed data-flow diagrams, abuse cases, Kubernetes workload threats, cloud IAM
policies, and incident exercises are added with their implementation phases.
