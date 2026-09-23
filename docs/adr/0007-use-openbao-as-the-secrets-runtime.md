# ADR-0007: Use OpenBao as the secrets runtime

- Status: accepted
- Date: 2026-09-23
- Decider: Hamid Gholami

## Context

Phase 2 needs one service for encrypted secret storage, machine authentication,
an online intermediate CA, dynamic PostgreSQL credentials, SSH client
certificates, human OIDC authentication, audit records, and snapshot-based
recovery. The roadmap allows Vault Community Edition or OpenBao, but operating
both would double security updates, configuration paths, tests, backup work, and
documentation without serving a second runtime requirement.

The required capabilities are available in OpenBao 2.6.2: integrated Raft
storage and snapshots, declarative audit devices, JWT/OIDC authentication, PKI,
the PostgreSQL database plugin, and SSH certificate signing. OpenBao is governed
as an open-source project and distributed under MPL-2.0. Official signed release
artifacts include Debian packages for the reference architecture.

Vault Community Edition remains a credible alternative and has a larger
industry footprint, but this repository does not currently require a feature
that is absent from OpenBao. Maintaining a second implementation solely for
product-name coverage would conflict with the repository's complexity and
no-cost open-source goals.

## Decision

Use OpenBao as the only Phase 2 secrets runtime. Start with exact release
`2.6.2`, verify its signed checksum and package provenance during dependency
setup, and use the official `bao` CLI and HTTP API without a custom compatibility
wrapper.

Run one explicitly non-HA OpenBao server in the `single-node-reference` profile
with integrated Raft storage. Use configuration-managed TLS, declarative audit
devices, and service settings. Manage security objects through the smallest
idempotent API boundary that keeps secret values out of source, command lines,
logs, and additional provider state.

Do not deploy Vault alongside OpenBao and do not claim continuous Vault
compatibility. A future Vault requirement is a migration: review its license and
features at that time, restore or recreate supported configuration through
documented interfaces, and rerun the complete behavior and recovery contract.

## Consequences

- Phase 2 has one service, CLI, security-update stream, configuration path, and
  backup format to own.
- The required implementation has a maintained, no-license-fee, OSI-approved
  open-source path.
- OpenBao-specific features or API divergence must be used deliberately; shared
  ancestry with Vault is not evidence of present or future compatibility.
- The portfolio demonstrates the underlying PKI, identity, dynamic-secret,
  short-lived-credential, audit, and recovery behaviors without maintaining a
  second product for name recognition.
- A later Vault migration has real test and operational cost. It is not hidden
  behind an abstraction that merely renames commands.

## Alternatives considered

- **Vault Community Edition only:** capable, maintained, and widely recognized,
  but source-available rather than OSI open source and not needed for any unique
  Phase 2 requirement.
- **Vault primary plus OpenBao compatibility tests:** rejected because the
  duplicate version, policy, plugin, integration, and recovery matrix adds
  ongoing cost before a second runtime consumer exists.
- **Selectable Vault/OpenBao wrapper:** rejected because it would encode the
  least common denominator, conceal meaningful divergence, and become another
  security-sensitive component.
- **Separate tools for PKI, dynamic database credentials, and SSH signing:**
  rejected because OpenBao already supplies the required cohesive policy and
  audit boundary.

## Validation and reversal

Phase 2 must prove on the authoritative reference environment that OpenBao
`2.6.2` can:

- run with TLS, integrated storage, and declarative audit configuration;
- snapshot and restore a non-production secret in isolation;
- hold an online intermediate whose private key is not exported;
- issue and revoke a dynamic PostgreSQL credential;
- sign a constrained, short-lived SSH client certificate; and
- authenticate a Keycloak user through OIDC with bounded policy mapping.

Reconsider the decision if a required contract cannot be implemented with a
maintained OpenBao release, the project no longer provides timely security
maintenance or signed reference-platform artifacts, or a concrete consumer
requires a Vault-only capability whose value exceeds the migration and ongoing
license cost.

## References

- [OpenBao 2.6.2 release](https://github.com/openbao/openbao/releases/tag/v2.6.2)
- [OpenBao installation](https://openbao.org/docs/install/)
- [OpenBao integrated storage](https://openbao.org/docs/concepts/integrated-storage/)
- [OpenBao declarative audit devices](https://openbao.org/docs/configuration/audit/)
- [OpenBao PKI setup](https://openbao.org/docs/secrets/pki/setup/)
- [OpenBao PostgreSQL database secrets](https://openbao.org/docs/secrets/databases/postgresql/)
- [OpenBao signed SSH certificates](https://openbao.org/docs/secrets/ssh/signed-ssh-certificates/)
- [OpenBao JWT/OIDC authentication](https://openbao.org/docs/auth/jwt/)
