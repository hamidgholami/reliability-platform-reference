# Phase 2 Plan: Trust, Secrets, and Identity

- Status: active; P2-01 and P2-02 accepted, with P2-03 next
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

## P2-00 phase-wide decision register

Resolve each choice before the work item that consumes it. A later service must
not block an earlier dependency slice when the two choices are independent.
P2-00 is therefore a rolling control track, not a sequential milestone that
must close before P2-01 or P2-02 can begin. It closes with the Phase 2 exit
review after every row has either been resolved or explicitly removed from
scope.

| Decision | Gate | Status |
| --- | --- | --- |
| BIND version and source | P2-01 | Use the Debian 13 stable/security `bind9` and `bind9-dnsutils` 9.20 package line; accept patched Debian revisions and record the installed version in acceptance evidence. |
| PostgreSQL version and source | P2-03 | Use Debian 13 stable/security `postgresql-17` and `postgresql-client-17`; accept patched Debian revisions and record the installed version in acceptance evidence. The Debian package was 17.11-0+deb13u1 when this decision was checked. |
| Keycloak version, installation, realm export, database ownership, and WebAuthn ceremony | P2-04 | Open; resolve before storing identity data. |
| OpenBao installation and bootstrap | P2-02 | Closed: use the signed OpenBao 2.6.3 native Debian package for the target architecture, integrated Raft storage, manual Shamir initialization, and no auto-unseal dependency. |
| Netcup API generation and maintained DNS-01 client | P2-05 | Open; it is not needed for private DNS and no custom ACME client is authorized. |
| Capacity | Every slice | Develop in the retained local Lima VM. P2-02 adds one 1-vCPU, 512-MiB, 4-GiB container and keeps AWS `t4g.small` plus 30-GiB `gp3`; measure before promotion and change the paid profile only after evidence of a capacity failure. |
| DNS bootstrap secrets | P2-01 | Generate one random TSIG value per zone and secondary in a mode-`0600` ignored runtime file. Pass that file independently to OpenTofu and Ansible; never recover a key from state or output. |
| Remaining bootstrap secrets and rotation | P2-02 onward | Closed for P2-02 by the secret inventory and ceremony in the OpenBao foundation runbook; later services extend that inventory before use. Bootstrap never depends on a healthy OpenBao instance to create OpenBao. |
| Secrets-service configuration owner | P2-02 | Closed: OpenTofu owns the instance, host-enforced network ACL, and DNS records; Ansible owns the guest and static service configuration; narrowly scoped Ansible HTTP API tasks own OpenBao objects; and humans retain root-key and seal custody. |
| Operator browser access | P2-04 | Required before browser acceptance. Prefer route-limited WireGuard with split DNS; resolve endpoint placement, peer custody, revocation, and profile-specific ingress before implementation. Do not expose private services publicly. |

Any choice that changes a platform or trust boundary requires an ADR. Version
and implementation details that stay within an accepted boundary belong in this
plan and the dependency inventory, not in an ADR.

## Work items

### P2-00 — Rolling capability, ownership, and bootstrap review

P2-00 governs every slice rather than representing an unfinished deployment.
For each consuming work item, resolve its rows in the register, extend the
secret inventory and recovery flow, record capacity assumptions, and add an ADR
only when an accepted architecture boundary changes. Phase-wide acceptance is
reviewed at P2-06: every dependency must close a named capability gap, have one
configuration owner, and have a test and removal or migration path. No service
is created merely to compare products.

### P2-02 readiness gate — accepted 2026-09-28

- [x] Advance the selected 2.6 release line from OpenBao 2.6.2 to 2.6.3 because
  the patch release contains published security fixes; this does not change the
  ADR-0007 product or architecture decision.
- [x] Select the official native Debian package for `amd64` or `arm64`, verify
  the signed checksum manifest against the pinned OpenBao release-key
  fingerprint, and verify the package checksum before installation.
- [x] Assign one owner to each layer: OpenTofu for the Incus resource, network
  ACL, and DNS data; Ansible for the guest and static configuration; Ansible
  HTTP API tasks for declarative OpenBao objects; and the human operator for
  root and seal ceremonies.
- [x] Keep the offline CA root and OpenBao Shamir material outside the repository
  and require protected, encrypted inputs for every ceremony. Do not introduce
  a cloud KMS merely to auto-unseal one reference node.
- [x] Define the bootstrap, rotation, recovery, redaction, and teardown contract
  in the [OpenBao foundation runbook](../runbooks/openbao-foundation.md) and
  update the threat model for the new trust boundary.
- [x] Keep the paid AWS profile at `t4g.small` and 30-GiB `gp3`; the bounded
  container request and retained-local measurements must justify any later
  increase.
- [x] Record that OpenBao removed `mlock` in 2.0.0. Rely on the package's
  `MemorySwapMax=0` service boundary and do not add obsolete capability grants
  or a meaningless `disable_mlock` setting.

Acceptance: the P2-02 implementation may begin without an unresolved product,
ownership, secret-bootstrap, recovery, capacity, or provenance decision.

### P2-01 — Private authoritative DNS

- [x] Select the Debian 13 BIND 9.20 package line and define authoritative-only
  guest configuration, protected TSIG input, and local-first promotion
  boundaries.
- [x] Enable the Incus network-zone server on a private, non-standard port
  reachable only from the platform network.
- [x] Add provider-owned forward and IPv4 reverse zones and attach them to the
  managed bridge.
- [x] Create only the two bounded BIND service instances required by the
  accepted DNS design, using stable addresses from the foundational range.
- [x] Configure BIND as authoritative secondary only: no public listener, open
  recursion, manual primary data, or unrelated zones.
- [x] Supply per-peer TSIG material through protected runtime inputs. Permit the
  provider to record the required value in protected local state, but never in
  output, logs, committed variables, or published evidence.
- [x] Generate Ansible inventory from provider output and configure each guest
  through the repository wrapper with diff mode and secret-safe tasks.
- [x] Validate authenticated AXFR, bounded refresh, forward and reverse
  answers, automatic record changes from Incus state, manual provider-owned
  records, and queries through either secondary.
- [x] Prove that one stopped secondary does not prevent queries to the other.
  Do not describe this as host-level HA.
- [x] Prove provider and Ansible idempotence plus bounded DNS teardown and clean
  recreation.

Acceptance: clients on the platform network resolve current forward and reverse
records through either BIND secondary; unauthorized transfer fails; no private
address is published in Netcup DNS; and no TSIG value appears in evidence.

Implementation note: Debian 13 supplies Incus 6.0 LTS, while DNS NOTIFY for
network zones first appeared in Incus 7.4. P2-01 therefore clamps BIND's
periodic refresh to the 120-second SOA value advertised by Incus 6.0 and proves
that bound. Adopting NOTIFY is deferred until it is available on a selected
supported LTS; a monthly feature release is not required for this capability.
The redacted
[local acceptance record](../evidence/phase-2-private-dns-local-acceptance.md)
captures the completed workstation run. Promotion to the real
`single-node-reference` environment remains part of Phase 2 final acceptance.

### P2-02 — Internal PKI and secrets foundation

- [x] Implement the reviewed operator-managed root workflow without committing
  or transferring custody of the root private key to the platform or CI.
- [x] Create one bounded secrets-service instance with TLS, integrated storage,
  swap disabled at the service boundary, a host-enforced Incus network ACL,
  and no public listener. Do not configure obsolete OpenBao `mlock` settings.
- [x] Initialize and unseal through an explicit human ceremony. Store recovery
  material outside the repository and outside ordinary command logs.
- [x] Enable at least one durable audit device before routine use and validate
  its permissions, rotation, and failure behavior.
- [x] Configure a versioned non-production KV path and narrowly scoped operator
  and machine policies.
- [x] Generate the online intermediate key inside the secrets service, sign only
  its CSR with the offline root, and publish the non-secret trust chain and CRL
  endpoints through private DNS.
- [x] Issue and renew one service certificate without exporting the intermediate
  private key.
- [x] Revoke the initial root token after recovery-capable administrative access
  is proven.

Acceptance: the selected service starts from documented inputs, serves only TLS,
records audited API use, issues a bounded leaf certificate from the online
intermediate, and no longer depends on the initial root token.

### P2-03 — Machine identity, dynamic secrets, and SSH certificates

#### Readiness decision — selected 2026-09-29

The [machine-authentication runbook](../runbooks/machine-auth.md) defines the
first executable slice and its credential cleanup.

Use the existing OpenBao certificate auth mount for one synthetic machine
identity on `smoke-01`. Generate its private key inside that instance and
exact-pin its 90-day self-signed client certificate to a dedicated role. Issue
tokens with a five-minute explicit maximum TTL and no default policy. The role
permits only the named PostgreSQL credential and SSH-signing paths introduced
below. It does not inherit the P2-02 `rpr-machine-read` KV policy. Replace the
pin before certificate expiry, and disable the role and revoke its tokens on
suspected key exposure. A recreated `smoke-01` needs a new key and pin. Do not
use the root-generation certificate for routine configuration or machine login.
Route the private DNS zone from `smoke-01` to the existing BIND secondaries,
while retaining the Incus bridge resolver for other names.

After retirement of the initial root token, configuration requires the
protected Shamir root-generation ceremony. Use its temporary root to install
the fixed machine policy and exact-pinned certificate role, then revoke the
root and recovery login before machine acceptance. A nominally scoped token
allowed to edit that policy or role could grant its own certificate broader
rights, so do not mint a configuration token for this operation. No persistent
operator certificate is introduced for this slice. A rerun before Keycloak
OIDC exists repeats the guarded ceremony. Keep the operator and machine
policies distinct. P2-04 will provide the ordinary human authentication path.

Install PostgreSQL 17 from Debian 13 stable/security on `pg-01`, its own
unprivileged Incus container at `10.20.0.21` with generated private DNS name
`pg-01.dev.apadanalab.de`. Bind PostgreSQL only to that private address. Use
PostgreSQL TLS and `pg_hba.conf` to restrict database, role, and source. The
host-enforced ACL permits TCP 5432 only from the private platform CIDR;
PostgreSQL separately accepts the OpenBao administrator from `bao-01` and the
dynamic test role from `smoke-01`, using its current Incus-reported address
rather than a copied lease. No cloud ingress or public DNS record is added.
Generate the PostgreSQL listener key inside `pg-01` and sign only its
public CSR with the existing online intermediate. Renew the leaf before
expiry and keep its private key on the instance. Local peer access by the
`postgres` operating-system account is the recovery route. The first dynamic
role reads one synthetic table in an `rpr_p203` database; later Keycloak
credentials require a separate role.
Create a non-superuser OpenBao database administrator with `CREATEROLE` and
administration of a test read-only group role. PostgreSQL's `CREATEROLE` is
broader than one database, so isolate this demonstration in its own instance
and give the OpenBao connection only one allowed dynamic role. Generate its
password outside Git and OpenTofu state, install it into OpenBao through a
protected API task, then remove the transfer copy. If OpenBao's encrypted state
is lost, reset that password through local peer administration and reconfigure
the connection; no static application password is issued or backed up.

Use `smoke-01` as the machine client and `ssh-test-01` as a disposable SSH
target at `10.20.0.221`. Incus publishes its private A/PTR records under
`ssh-test-01.dev.apadanalab.de`; a host-enforced ACL allows TCP 22 only from
the private platform CIDR. No public ingress or DNS record is added.
Configure one non-sudo test account and one OpenBao SSH client CA. Ansible
installs only the public CA key and restrictive `sshd` settings on the target.
Generate the SSH CA with OpenBao's explicit `ssh-ed25519` key type; its default
CA key type is RSA. Generate the client's temporary signing key and the test
target's host key with `ssh-keygen -t ed25519`. Configure `sshd` to offer only
the Ed25519 host key and accept only Ed25519 user certificates. Set the signing
role's `allowed_user_key_lengths` to `{"ed25519": 0}` so OpenBao cannot sign
an RSA client key. Assert the CA public key, client public key, and host public
key are all `ssh-ed25519` before acceptance.

The signing role fixes that account as its sole principal, limits TTL to five
minutes, and allows no forwarding or user-selected extensions. OpenBao keeps
the SSH CA private key in encrypted Raft storage and snapshots; rotate it and
replace the target's trusted public key if exposed. Remove the target and test
key pair after acceptance; retain only redacted evidence.

The current Incus project limit is four containers, four CPU shares, 1536 MiB,
and 12 GiB, all allocated by the existing four containers. Review and raise
these limits only for the PostgreSQL container and the temporary SSH target.
Measure host and per-service use in the 4-GiB Lima VM before any AWS promotion;
the 2-GiB AWS reference host is not assumed to fit this slice. OpenTofu owns
the new instances, addresses, and network ACLs; Ansible owns guest packages,
configuration, protected files, and OpenBao API objects. No new runtime or
custom credential service is needed.

- [x] Implement one machine-authentication path appropriate to the standalone
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

- [ ] Provide private operator access before browser testing. Prefer WireGuard,
  route only the selected platform CIDR, conditionally resolve only the private
  platform zone, reject overlapping client networks, and keep service listeners
  private. Document endpoint placement, peer enrollment, rotation, revocation,
  and teardown before opening the VPN listener.
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

Acceptance: an enrolled privileged user reaches Keycloak by private DNS and
private address from a declared workstation, completes all required factors,
and receives only the mapped role. An ordinary or incompletely authenticated
user cannot obtain privileged secrets-service access. Revoking the workstation
VPN peer removes private route and DNS access without publishing the service.

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

## Deferred workstation ergonomics

- [ ] Evaluate mise as an optional pinned-tool and environment-profile frontend
  after the active service slice. Keep Make as the sole task and safety
  interface, require explicit profile selection, keep credentials and personal
  paths in ignored local configuration, and adopt mise only if it replaces
  duplicated version or export configuration rather than adding another source
  of truth.

This evaluation is not a P2-02 or Phase 2 exit gate. CI and documented Make
commands must remain usable without shell activation or hidden environment
selection.

## Verification interface

The P2-02 readiness gate fixes the OpenBao target names in its runbook. The
existing public foundation interface remains supported:

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
- [Debian 13 PostgreSQL 17 package](https://packages.debian.org/trixie/database/postgresql-17)
- [PostgreSQL 17 role attributes](https://www.postgresql.org/docs/17/role-attributes.html)
- [OpenBao 2.6 certificate authentication API](https://openbao.org/docs/2.6.x/api/auth/cert/)
- [OpenBao 2.6 PostgreSQL database plugin](https://openbao.org/docs/2.6.x/secrets/databases/postgresql/)
- [OpenBao 2.6 SSH signing API](https://openbao.org/docs/2.6.x/api/secret/ssh/)
