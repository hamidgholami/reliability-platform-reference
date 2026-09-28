# OpenBao Foundation Runbook

This runbook is the P2-02 implementation contract for one explicitly non-HA
OpenBao service. It defines ownership and ceremonies before automation is
enabled; it does not contain real keys, tokens, shares, or deployment evidence.

## Fixed boundary

- The service instance is `bao-01` at `10.20.0.20` on `platform0` with the
  private alias `openbao.dev.apadanalab.de`.
- The initial limit is one vCPU, 512 MiB of memory, and a 4 GiB root disk.
- OpenBao 2.6.3 uses integrated Raft storage on the single instance. This is not
  an HA topology.
- The API listens with TLS only on the private service address. A host-enforced
  Incus network ACL assigned to the shared bridge accepts TCP 8200 only from
  the platform CIDR, and the guest NIC overrides its default to reject other
  new inbound traffic. No public listener, public DNS address, port forwarding,
  or public cloud ingress is added.
- The package-provided systemd unit sets `MemorySwapMax=0`. OpenBao removed
  `mlock` in 2.0.0, so P2-02 does not add `CAP_IPC_LOCK` or the obsolete
  `disable_mlock` setting.
- Auto-unseal is deferred. Adding a KMS solely for this single reference node
  would create a circular cloud dependency, another credential boundary, and
  cost without satisfying a current requirement.

The retained Lima host remains the daily integration environment. The AWS
reference stays at `t4g.small` with a 30 GiB encrypted `gp3` root volume until
measured CPU, memory, disk, or duration evidence requires a reviewed change.

## Ownership

| Layer | Owner | Boundary |
| --- | --- | --- |
| Incus instance, profile, address, network ACL, and private DNS alias | OpenTofu | Declarative provider state; no service secrets |
| Package, TLS files, Raft path, systemd, audit file, and rotation | Ansible | Idempotent guest configuration with secret tasks hidden from output and diff |
| KV, policy, token role, PKI mounts, URLs, and issuance roles | Narrow Ansible HTTP API tasks | Idempotent API objects; token read from a mode-`0600` protected file |
| Offline CA root, Shamir initialization, unseal, root-token retirement, and custody | Human operator | Interactive ceremony and encrypted storage outside the checkout |

No OpenBao provider, custom API client, parallel Vault path, or second secrets
service is introduced. The future Keycloak slice replaces temporary human token
access with OIDC; it does not change the ownership of machine policy.

## Installation provenance

Automation downloads the official OpenBao release public key, checksum
manifest, detached manifest signature, and native Debian package for the target
architecture. It must:

1. require primary key fingerprint
   `66D15FDD87287219C8E15478D200CD702853E6D0`;
2. verify `checksums.txt.gpgsig` before trusting the manifest;
3. accept only `openbao_2.6.3_linux_amd64.deb` with SHA-256
   `5fc11b4aa2bd51eccfda8a694131d88410d3f3d60420aadb2d8c31558db03acd`
   or `openbao_2.6.3_linux_arm64.deb` with SHA-256
   `6822f59749cc919b820bad472a70ba55ff4f128072556a97f8d204cc9b9d55ef`;
4. reject every other architecture, filename, version, key fingerprint, or
   checksum; and
5. record only the installed version, architecture, and verification result in
   redacted evidence.

## Secret inventory

| Material | Producer and consumers | Storage and backup | Rotation or retirement | Evidence rule |
| --- | --- | --- | --- | --- |
| Root private key and passphrase | Guarded operator workflow; root signs only approved leaves, intermediates, and its CRL | Protected workstation storage during bootstrap plus two independently recoverable encrypted backups, with the passphrase held separately; never on the platform | Replace before expiry or after suspected exposure; remove the old root from trust only after migration | Never publish the key, passphrase, filesystem path, or unredacted command output |
| Root certificate and CRL | Offline ceremony; clients and OpenBao PKI consume public copies | Published trust bundle and recovery kit; safe to back up with configuration | Reissue CRL on intermediate revocation; distribute replacement root deliberately | Certificate, fingerprint, serial, validity, and CRL are publishable |
| Bootstrap listener private key and certificate | Operator-root workflow; Ansible installs them for first TLS startup | Mode-`0600` runtime input outside Git; no long-term backup | Replace with an online-intermediate leaf after PKI bootstrap, revoke when applicable, then delete the runtime copy | Publish only subject, issuer, serial, validity, and fingerprints |
| Shamir unseal shares | `bao operator init`; human custodians decrypt and present a threshold | Each encrypted share is stored separately outside Git and ordinary backups | Rotate after custodian change or suspected exposure; invalidate the prior set after validation | Never publish encrypted or decrypted shares, QR codes, paths, or command output |
| Initial root token | `bao operator init`; used only for first policy and token-role configuration | PGP-encrypted ceremony output; decrypt only for the bounded bootstrap session | Revoke after a scoped bootstrap administrator and root-regeneration recovery are proven; no backup afterward | Record only the revocation result and token accessor when safe |
| Bootstrap administrator token | Created under the initial root token; consumed by protected API automation | Mode-`0600` file outside Git for one bounded work session | Short explicit maximum TTL, no renewal; revoke on completion or exposure | Never publish the value; accessor, policy names, TTL, and revocation result are publishable |
| Online-intermediate private key | Generated and retained by the OpenBao PKI engine | Encrypted Raft storage and encrypted snapshots; never exported | Rotate before expiry or on compromise; offline root revokes and replaces it | Publish only CSR, certificates, fingerprints, serials, validity, and CRL URLs |
| Service leaf private keys | Generated for the consuming service or by its approved issuance flow | Only the consuming service's protected runtime; backup is not required for replaceable leaves | Renew before expiry and revoke on exposure or decommission | Never publish keys or full issuance responses |
| KV test value | Synthetic producer through scoped API; bounded test consumer | Versioned KV and encrypted Raft snapshots | Delete versions and metadata after recovery tests | Publish only paths, versions, timestamps, and pass/fail results |
| Raft snapshot | OpenBao operator API; isolated restore consumes it | Encrypted backup storage outside Git and outside the source instance | Replace on schedule; destroy isolated restore copies after validation | Treat the entire snapshot as secret; publish checksum and test metadata only |
| Audit log | OpenBao declarative file audit device; operator and later log pipeline consume it | Root/OpenBao-protected local file and encrypted backup | Rotate under a documented policy; retain only for the declared test window | Publish counts and redacted validation, never raw records |

Later Phase 2 slices must extend this table before introducing database,
Keycloak, DNS-provider, or machine-authentication credentials.

## Ordered bootstrap

1. Verify the signed repository revision, target host identity, time sync, and
   OpenBao release provenance.
2. On the trusted operator workstation, create or recover the root CA and its
   CA database through the guarded
   [operator-root workflow](offline-root-ca.md). Produce the public root
   certificate, current CRL, and one-year bootstrap listener certificate
   for the reviewed private names and address. Back up the root state to
   encrypted offline storage; neither the platform nor CI receives custody.
3. OpenTofu creates only the bounded instance, profile, address, network ACL,
   and private DNS data.
4. Ansible installs and verifies OpenBao, places the supplied TLS material,
   configures integrated Raft storage, declarative file audit, and rotation,
   then starts the sealed service behind the provider-owned network ACL.
5. The human operator runs manual Shamir initialization with three PGP
   recipients and a two-share threshold. The initial root token is also PGP
   encrypted. Plaintext initialization output must not reach a terminal log.
6. Two custodians or independently stored identities decrypt and enter shares
   interactively. Shares are never command arguments, Make variables, Ansible
   variables, or shell-history entries.
7. The initial root token creates the smallest bootstrap-administrator policy
   and one short-expiry orphan token. Protected API automation enables KV v2,
   configures `pki_int`, policies, URLs, and bounded issuance roles.
8. OpenBao generates the intermediate private key internally and emits only a
   CSR. The offline root signs it with a bounded path length and validity, then
   returns the intermediate certificate and chain.
9. OpenBao imports the signed intermediate, publishes CA and CRL endpoints, and
   issues the replacement service leaf. Ansible installs that leaf without
   exporting the intermediate key and removes the bootstrap listener key from
   the operator runtime directory.
10. Validate scoped administration and a quorum-based root-regeneration
    ceremony, revoke the generated recovery root token, then revoke the initial
    root token. Routine automation must fail if only that retired token exists.

The service-foundation slice exposes `configure-openbao`, `openbao-status`, and
`validate-openbao`. Later ceremony and API-object slices add
`initialize-openbao`, `unseal-openbao`, and `bootstrap-openbao` only when their
implementations are complete. Mutation targets require the selected profile,
target identity, protected input locations, expected effect, and exact
confirmation. Status and validation remain read-only.

Prepare a mode-`0700` directory outside the checkout containing `ca.crt`,
`ca.crl`, `tls.crt`, and the unencrypted service key `tls.key`, each mode
`0600`. The listener certificate must chain to `ca.crt`, remain valid for more
than seven days, be absent from the current CRL, match `tls.key`, and contain
`openbao.dev.apadanalab.de`,
`bao-01.dev.apadanalab.de`, and `10.20.0.20` as subject alternative names.
Validate these inputs using `make validate-openbao-bootstrap-tls`. After
`make apply` has generated the ignored inventory, configure and inspect the
still-uninitialized, sealed service with:

```sh
PROFILE=workstation-validation \
INCUS_CONFIG_DIR=/absolute/path/to/incus-client \
INCUS_REMOTE=rpr-target \
OPENBAO_TLS_INPUT_DIR=/absolute/protected/path \
CONFIRM=configure-openbao-workstation-validation-rpr-target \
make configure-openbao

PROFILE=workstation-validation \
INCUS_CONFIG_DIR=/absolute/path/to/incus-client \
INCUS_REMOTE=rpr-target \
make openbao-status

PROFILE=workstation-validation \
INCUS_CONFIG_DIR=/absolute/path/to/incus-client \
INCUS_REMOTE=rpr-target \
make validate-openbao
```

The configuration wrapper validates the protected input before invoking
Ansible. Ansible independently verifies the signed checksum manifest and exact
package checksum, prevents the Debian package from generating its fallback
self-signed key, installs integrated Raft and declarative file-audit
configuration, and starts the TLS-only service. These targets do not initialize
or unseal OpenBao.

## Audit and recovery checks

The declarative file audit device exists in the server configuration before
routine API configuration. Local acceptance verifies ownership and mode,
rotation with continued writes, and OpenBao's fail-closed response when its only
audit device is unavailable. The failure exercise must restore permissions and
health before any later slice proceeds.

Recovery uses a fresh isolated instance with no production DNS alias or client
route. Verify the snapshot checksum, restore it, present the external Shamir
quorum, and confirm one versioned synthetic KV value plus the non-secret PKI
metadata. Destroy the isolated copy after evidence is redacted. A snapshot that
has not passed this exercise is not described as a backup.

## Rollback and removal

Before destroying `bao-01`, revoke active test leases, tokens, and leaf
certificates; revoke or replace the online intermediate if trust is ending;
capture and verify the required encrypted snapshot; remove DNS aliases and
client trust; and delete protected runtime copies of bootstrap material.
OpenTofu may then remove only its state-owned instance and records. It never
deletes the offline-root kit, Shamir custody material, or external backups.

Migration to Vault or another service is a reviewed replacement: export or
recreate supported policy and PKI metadata through documented interfaces,
reissue credentials, and rerun recovery and behavior acceptance. P2-02 does not
maintain a compatibility abstraction.

## References

- [OpenBao 2.6.3 release](https://github.com/openbao/openbao/releases/tag/v2.6.3)
- [OpenBao 2.6 installation](https://openbao.org/docs/2.6.x/install/)
- [Integrated Raft storage](https://openbao.org/docs/2.6.x/configuration/storage/raft/)
- [Declarative audit devices](https://openbao.org/docs/2.6.x/configuration/audit/)
- [Operator initialization](https://openbao.org/docs/2.6.x/commands/operator/init/)
- [OpenBao 2.0 mlock removal](https://openbao.org/docs/release-notes/2-0-0/)
