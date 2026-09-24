# Phase 2 Plan: Trust, Secrets, and Identity

- Status: active; P2-01 private DNS implementation started
- Started: 2026-09-23
- Owner: Hamid Gholami
- Default deployment profile: `single-node-reference`
- Optional test profile: `workstation-validation`

## Outcome

Extend the proven standalone Incus foundation with the smallest coherent trust
chain:

- private authoritative DNS derived from Incus state;
- internal certificate issuance with an offline root boundary;
- one secrets service selected for the active profile;
- human identity through Keycloak and PostgreSQL;
- machine authentication, dynamic database credentials, and short-lived SSH
  certificates; and
- backup and isolated restore evidence for the state introduced in this phase.

Phase 2 must prove that a human and a machine can authenticate through distinct,
least-privilege paths without storing reusable credentials in Git or depending
on the future workload Kubernetes cluster. It remains a single-host reference
environment and makes no high-availability or production-readiness claim.

## Delivery principle

Apply [ADR-0006](../adr/0006-use-progressive-single-node-delivery.md). Complete
and validate one dependency-ordered slice before creating the next service.
Planning the complete phase does not authorize pre-creating every future
instance, role, directory, or Make target.

The promotion path is local-first:

| Level | Purpose | Required environment |
| --- | --- | --- |
| Workstation checks | Formatting, linting, syntax, policy, and offline safety contracts | macOS and CI |
| Daily integration | Repeated service-role and provider feedback; keep one Lima VM between sessions and stop it when idle | `workstation-validation` |
| Clean local acceptance | Recreate the Lima VM and active slice from empty state before closing each work item | `workstation-validation` |
| AWS promotion | Prove the completed slice from empty cloud state at milestone boundaries | `single-node-reference` |

Use real services for boundaries that mocks cannot establish, but do not build a
custom test platform around behavior already owned by BIND, Keycloak,
PostgreSQL, or the selected secrets service. Tests protect this repository's
configuration, ownership, access, lifecycle, and recovery contracts.

Daily development does not recreate the AWS host or the Lima VM. Use the same
OpenTofu and Ansible artifacts in both profiles, reset only the smallest layer
needed for the current test, and reserve a full Lima deletion or AWS deployment
for clean acceptance. Do not build custom images, caches, or a standing cloud
environment merely to shorten bootstrap time.

## Accepted starting gates

These decisions are already authoritative and are not reopened by default:

- Netcup remains registrar and public authoritative DNS provider for
  `apadanalab.de`.
- Incus network zones are the hidden primary for the private forward and reverse
  zones. BIND 9 secondaries serve ordinary authoritative queries.
- Kubernetes CoreDNS is not part of Phase 2.
- Foundational identity and secrets services run in Incus instances outside the
  future workload cluster.
- The official Incus provider owns zones, zone records, network attachment,
  service instances, and other Incus API resources. Ansible owns guest operating
  systems, service configuration, protected key files, and Incus server-global
  configuration.
- The reference environment remains one standalone Incus host. Two BIND
  instances on that host demonstrate independent DNS processes and transfer
  behavior, not physical failure-domain redundancy.
- OpenTofu remains the IaC command. Do not introduce a second IaC runtime or a
  general abstraction over provider CLIs.
- [ADR-0007](../adr/0007-use-openbao-as-the-secrets-runtime.md) selects OpenBao
  as the one Phase 2 secrets runtime. Vault is not deployed in parallel.
- The internal CA root stays offline. A networked secrets service may hold only
  the online intermediate needed for routine issuance.

## Explicit non-goals

Phase 2 does not include:

- an Incus cluster, multi-host HA, Ceph, OVN, or a production profile;
- Kubernetes, CoreDNS, cert-manager, GitOps, or Velero;
- Jenkins, an approval-broker service, artifact stores, or deployment pipelines;
- a public recursive resolver or publication of private addresses in public DNS;
- a service mesh, SPIFFE platform, LDAP directory, or custom identity protocol;
- simultaneous Vault and OpenBao deployments or a large compatibility wrapper;
- automatic custody of offline-root keys, unseal or recovery shares, TOTP seeds,
  WebAuthn credentials, or break-glass material; or
- a claim that two containers on one Incus host provide DNS, identity, database,
  or secrets high availability.

Phase 2 creates the `staging-approver` and `production-approver` identity model
and proves the required authentication claims. The application that consumes an
approval belongs with the Phase 4 delivery path and is not pulled into this
phase.

## P2-00 decision gates

Resolve each choice before the work item that consumes it. A later service must
not block an earlier dependency slice when the two choices are independent.

| Decision | Gate | Status |
| --- | --- | --- |
| BIND version and source | P2-01 | Use the Debian 13 stable/security `bind9` and `bind9-dnsutils` 9.20 package line; accept patched Debian revisions and record the installed version in acceptance evidence. |
| PostgreSQL version and source | P2-03 | Open; prefer the Debian 13 package when it satisfies the dynamic-credential contract. |
| Keycloak version, installation, realm export, database ownership, and WebAuthn ceremony | P2-04 | Open; resolve before storing identity data. |
| OpenBao installation and bootstrap | P2-02 | Open beyond the accepted OpenBao 2.6.2 product choice. |
| Netcup API generation and maintained DNS-01 client | P2-05 | Open; it is not needed for private DNS and no custom ACME client is authorized. |
| Capacity | Every slice | Develop in the retained local Lima VM. Keep AWS `t4g.small` until measurements show a failure or an upstream minimum requires a change. |
| DNS bootstrap secrets | P2-01 | Generate one random TSIG value per zone and secondary in a mode-`0600` ignored runtime file. Pass that file independently to OpenTofu and Ansible; never recover a key from state or output. |
| Remaining bootstrap secrets and rotation | P2-02 onward | Open; bootstrap must not require a healthy secrets service to create that same service. |
| Secrets-service configuration owner | P2-02 | Open; prefer narrowly scoped idempotent Ansible or HTTP API tasks over another provider. |
| Operator access | P2-01 | Validate DNS from the platform network through Incus execution. Do not expose BIND publicly. Revisit a private VPN only when browser-based P2-04 access demonstrates the need. |

Any choice that changes a platform or trust boundary requires an ADR. Version
and implementation details that stay within an accepted boundary belong in this
plan and the dependency inventory, not in an ADR.

## Work items

### P2-00 — Capability, ownership, and bootstrap review

- [x] Select OpenBao 2.6.2 as the single Phase 2 secrets runtime in ADR-0007;
  retain Vault as a documented migration, not a parallel compatibility matrix.
- [ ] Resolve each decision gate before its consuming work item, using maintained
  upstream documentation and only the runtime spikes needed to distinguish
  alternatives.
- [ ] Map every new secret-bearing value to its producer, consumers, storage,
  rotation, revocation, backup, and evidence-redaction rules.
- [ ] Define the ordered bootstrap and recovery data flows and update the threat
  model with the implemented boundaries.
- [ ] Record exact resource assumptions and cost impact before changing the AWS
  reference size or lifetime.
- [ ] Add or supersede ADRs only where the accepted architecture changes.

Acceptance: every Phase 2 dependency closes a named capability gap, has one
configuration owner, and has a test and removal or migration path. No service is
created merely to compare products.

### P2-01 — Private authoritative DNS

- [x] Select the Debian 13 BIND 9.20 package line and define authoritative-only
  guest configuration, protected TSIG input, and local-first promotion
  boundaries.
- [ ] Enable the Incus network-zone server on a private, non-standard port
  reachable only from the platform network.
- [ ] Add provider-owned forward and IPv4 reverse zones and attach them to the
  managed bridge.
- [ ] Create only the two bounded BIND service instances required by the
  accepted DNS design, using stable addresses from the foundational range.
- [ ] Configure BIND as authoritative secondary only: no public listener, open
  recursion, manual primary data, or unrelated zones.
- [ ] Supply per-peer TSIG material through protected runtime inputs. Permit the
  provider to record the required value in protected local state, but never in
  output, logs, committed variables, or published evidence.
- [ ] Generate Ansible inventory from provider output and configure each guest
  through the repository wrapper with diff mode and secret-safe tasks.
- [ ] Validate authenticated AXFR, NOTIFY-driven refresh, forward and reverse
  answers, automatic record changes from Incus state, manual provider-owned
  records, and queries through either secondary.
- [ ] Prove that one stopped secondary does not prevent queries to the other.
  Do not describe this as host-level HA.
- [ ] Prove provider and Ansible idempotence plus bounded DNS teardown and clean
  recreation.

Acceptance: clients on the platform network resolve current forward and reverse
records through either BIND secondary; unauthorized transfer fails; no private
address is published in Netcup DNS; and no TSIG value appears in evidence.

### P2-02 — Internal PKI and secrets foundation

- [ ] Implement the reviewed offline-root procedure without committing or
  automating custody of the root private key.
- [ ] Create one bounded secrets-service instance with TLS, integrated storage,
  memory locking where supported, a host firewall boundary, and no public
  listener.
- [ ] Initialize and unseal through an explicit human ceremony. Store recovery
  material outside the repository and outside ordinary command logs.
- [ ] Enable at least one durable audit device before routine use and validate
  its permissions, rotation, and failure behavior.
- [ ] Configure a versioned non-production KV path and narrowly scoped operator
  and machine policies.
- [ ] Generate the online intermediate key inside the secrets service, sign only
  its CSR with the offline root, and publish the non-secret trust chain and CRL
  endpoints through private DNS.
- [ ] Issue and renew one service certificate without exporting the intermediate
  private key.
- [ ] Revoke the initial root token after recovery-capable administrative access
  is proven.

Acceptance: the selected service starts from documented inputs, serves only TLS,
records audited API use, issues a bounded leaf certificate from the online
intermediate, and no longer depends on the initial root token.

### P2-03 — Machine identity, dynamic secrets, and SSH certificates

- [ ] Implement one machine-authentication path appropriate to the standalone
  reference profile, with short token TTLs and no shared human identity.
- [ ] Create PostgreSQL on its own bounded service instance and establish the
  minimum administrative bootstrap outside application credentials.
- [ ] Configure the database secrets engine and prove creation, use, expiry, and
  revocation of one dynamic PostgreSQL credential.
- [ ] Configure an SSH client CA and one constrained signing role with fixed
  principals, short TTL, and restrictive extensions.
- [ ] Distribute `TrustedUserCAKeys` and an explicitly restricted test account
  to one disposable target through Ansible.
- [ ] Prove that an allowed certificate works and that an expired certificate,
  wrong principal, excessive TTL, or forbidden extension is rejected.
- [ ] Remove ephemeral private keys and certificates after each test.

Acceptance: a machine can obtain only the dynamic database credential and SSH
certificate allowed by its policy, and expiry or revocation removes access
without rotating a shared static deployment key.

### P2-04 — Keycloak identity and OIDC integration

- [ ] Deploy one Keycloak instance backed by the Phase 2 PostgreSQL service and
  protected by the accepted TLS and private-DNS path.
- [ ] Manage realm, client, group, role, and authentication-flow configuration
  from reviewed, secret-free source while keeping bootstrap credentials out of
  Git and logs.
- [ ] Require password, personal TOTP, and WebAuthn for privileged approvers.
  Prevent first-login enrollment from being mistaken for proof of a factor that
  was already enrolled and verified.
- [ ] Create separate `staging-approver` and `production-approver` roles and
  verify their OIDC claims with synthetic public identities.
- [ ] Configure Keycloak as the human OIDC authority for the selected secrets
  service and map groups to narrowly scoped policies.
- [ ] Test unauthorized, missing-factor, stale-session, disabled-user, and
  recovery cases. Physical WebAuthn enrollment is an explicit human acceptance
  step and its credential data is never published.
- [ ] Keep email self-service disabled until a real external SMTP relay exists;
  Phase 2 does not operate a mail server.

Acceptance: an enrolled privileged user must complete all required factors and
receives only the mapped role; an ordinary or incompletely authenticated user
cannot obtain privileged secrets-service access.

### P2-05 — Public certificate automation and trust distribution

- [ ] Use the reviewed Netcup DNS API path to create and remove only scoped ACME
  DNS-01 challenge records. Never publish private service addresses.
- [ ] Store the DNS API credential in the selected secrets service after
  bootstrap and prevent it from entering CI, process arguments, plans, logs, or
  evidence.
- [ ] Obtain a publicly trusted certificate only for a justified browser-facing
  private service. Continue to use the internal CA for private machine identity.
- [ ] Distribute the internal trust bundle to declared clients, validate renewal
  before expiry, exercise leaf revocation, and document intermediate rotation.
- [ ] Verify DNS-01 cleanup after success and failure.

Acceptance: the selected private endpoint presents the intended certificate,
renewal and cleanup are repeatable, and public DNS contains only safe ownership
or challenge records.

### P2-06 — Recovery, operator workflow, and acceptance evidence

- [ ] Add the smallest public Make interface needed for Phase 2 preflight,
  mutation, validation, backup, restore, and teardown; keep targets explicit and
  fail closed on profile and confirmation mismatches.
- [ ] Back up the selected secrets service using its supported snapshot
  mechanism and PostgreSQL using an application-consistent dump.
- [ ] Preserve required Keycloak realm configuration in source and identity data
  in the PostgreSQL backup; do not treat a realm export alone as a database
  backup.
- [ ] Restore a non-production secret and the identity database into an isolated
  environment, then validate OIDC login without re-enabling stale sessions or
  credentials.
- [ ] Exercise certificate-chain recovery without placing the offline root key
  in ordinary automation.
- [ ] Run the complete Phase 2 path twice where idempotence applies, record
  resource use and duration, and prove bounded teardown and clean recreation.
- [ ] Publish one redacted acceptance record containing outcomes and limitations,
  not raw logs, state, tokens, identities, certificates, or recovery material.

Acceptance: DNS, TLS, human and machine authentication, dynamic database
credentials, and SSH certificates work after clean recreation; a selected
secret and Keycloak identity state pass isolated restore; and final teardown
leaves no live project-owned cloud resources.

## Security and secret-handling rules

- Runtime secret files live only below an ignored operator-controlled directory,
  use mode `0600`, and are removed when the operation ends unless they are an
  explicitly protected recovery artifact.
- OpenTofu state and saved plans remain secret-bearing, mode-restricted, local
  artifacts for this profile. They are never uploaded as evidence or read by
  Ansible to recover a secret.
- Tasks that handle TSIG, API credentials, bootstrap tokens, unseal or recovery
  material, database passwords, TOTP data, or private keys use `no_log: true`
  and `diff: false`.
- No secret is accepted as a command-line argument or Make variable that appears
  in shell history. Prefer protected files or a tool's standard secure input.
- Initial credentials have an explicit retirement event. A bootstrap credential
  that silently becomes a permanent operator credential fails acceptance.
- Public CI receives no infrastructure, DNS, identity, hardware-token, or
  secrets-service credentials.
- New listeners are private by default. Opening a public inbound port requires a
  documented threat, cost, and teardown review.

## Cost and capacity rules

- Run workstation checks before every paid deployment session.
- Reuse the Phase 1 AWS cost, expiry, confirmation, destroy, and orphan gates.
- Record a fresh price estimate for any larger instance or longer test window.
- Measure host and per-service CPU, memory, disk, and duration at each accepted
  slice. Do not size the final Phase 2 topology from product minimums alone.
- Destroy the ephemeral AWS environment after the planned acceptance session.
  No identity or secrets service becomes a standing public cloud resource by
  default.

## Verification interface

P2-00 chooses exact new target names before implementation. The existing public
foundation interface remains supported:

```sh
make doctor
make check
make aws-plan PROFILE=single-node-reference
make aws-apply PROFILE=single-node-reference
make preflight
make baseline
make bootstrap-incus
make plan PROFILE=single-node-reference
make apply PROFILE=single-node-reference
make validate PROFILE=single-node-reference
```

Add service-specific targets only when their work item begins. Every mutating
target must display its host, profile, service boundary, secret inputs, expected
cost impact, and exact confirmation. `make check` remains non-mutating and
credential-free.

## Rollback and teardown boundaries

- Provider destroy may remove only provider-owned Phase 2 Incus instances,
  zones, records, and attachments represented in the selected state. It must not
  uninstall Incus or delete unrelated resources.
- Ansible rollback does not delete service data by default. Destructive
  reinitialization or restore requires a separate exact confirmation and a
  verified backup.
- DNS rollback removes forwarding and transfer relationships before deleting
  zones or secondaries. Public ACME challenge records are removed through the
  same scoped API path that created them.
- Secrets-service rollback revokes issued leases, tokens, certificates, and
  machine identities before instance destruction. Offline-root and recovery
  custody remains outside provider destroy.
- Identity rollback disables OIDC clients and privileged test users before
  database teardown. It does not claim that deleting a realm revokes already
  issued external credentials unless the dependent service validates that
  behavior.
- AWS destroy remains last and is followed by the existing orphan check.

## Phase 2 exit criteria

Phase 2 is complete only when:

- all local and CI checks pass;
- the selected runtime dependencies and ownership boundaries are documented;
- private forward and reverse DNS resolve through either authenticated BIND
  secondary and reject unauthorized transfer;
- the offline-root and online-intermediate boundary issues, renews, revokes, and
  recovers a test certificate;
- the selected secrets service uses TLS, durable audit, least-privilege human
  and machine auth, and no active initial root token;
- one dynamic PostgreSQL credential and one constrained SSH certificate pass
  positive, expiry, and authorization tests;
- Keycloak enforces the accepted password, TOTP, and WebAuthn flow for privileged
  roles and supplies bounded OIDC access to the secrets service;
- a non-production secret and Keycloak identity database pass isolated restore;
- repeated configuration has no unexplained drift;
- resource usage, duration, limitations, rollback, and redacted acceptance
  evidence are published; and
- no Kubernetes, Jenkins, approval-broker, artifact, observability, or later
  phase implementation begins early.

## References

- [Incus network zones](https://linuxcontainers.org/incus/docs/main/howto/network_zones/)
- [BIND 9 Administrator Reference Manual](https://bind9.readthedocs.io/)
- [Netcup DNS API](https://www.netcup.com/en/helpcenter/documentation/domain/our-api)
- [Keycloak Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [Vault documentation](https://developer.hashicorp.com/vault/docs)
- [OpenBao documentation](https://openbao.org/docs/)
