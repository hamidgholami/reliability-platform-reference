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
- The API listens with TLS only on the private service address. An Incus ACL
  assigned to the shared bridge restricts routed ingress to TCP 8200 from the
  platform CIDR, and the guest NIC rejects unmatched routed ingress. Bridge
  ACLs do not filter traffic between containers on the same bridge; TLS and
  OpenBao authentication enforce that service boundary. No public listener,
  public DNS address, port forwarding, or public cloud ingress is added.
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
| Shamir unseal share | `bao operator init`; the human operator decrypts and presents it | PGP-encrypted to a dedicated passphrase-protected recovery key outside Git; back up the complete recovery directory twice | Rekey after suspected exposure or before adding real independent custodians | Never publish the encrypted or decrypted share, recovery key, passphrase, path, or command output |
| Initial root token | `bao operator init`; used only for first policy and token-role configuration | PGP-encrypted to the same dedicated recovery key; decrypt only as a stream for the bounded bootstrap session | Revoke after a scoped bootstrap administrator and root-regeneration recovery are proven; no backup afterward | Record only the revocation result and token accessor when safe |
| Root-generation client credential | Guarded retirement workflow; OpenBao certificate auth exact-pins its public certificate | Self-signed client certificate and PGP-encrypted private key in the protected recovery kit outside Git; back up with the Shamir material | Five-year certificate; replace before expiry or immediately after suspected exposure | Publish only its subject, validity, and the fact that exact pinning succeeded |
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
5. The guarded operator workflow creates a dedicated passphrase-protected
   OpenPGP recovery key on the workstation. OpenBao initializes with one
   Shamir share and a threshold of one, encrypting both that share and the
   initial root token before they leave the service. The encrypted response and
   encrypted secret-key export remain outside Git under the protected operator
   directory.
6. The guarded unseal workflow decrypts the share as a stream and presents it
   through standard input. The share is never a command argument, Make or
   Ansible variable, plaintext file, shell-history entry, or terminal output.
   A 1-of-1 seal truthfully matches this single-operator reference lab; it is a
   single point of custody, not production quorum. Rekey to independently held
   threshold shares before claiming multi-operator or production operation.
7. The initial root token creates the smallest bootstrap-administrator policy
   and one short-expiry orphan token. Protected API automation enables KV v2,
   configures `pki_int`, policies, URLs, and bounded issuance roles.
8. OpenBao generates the intermediate private key internally and emits only a
   CSR. The offline root signs it with a bounded path length and validity, then
   returns the intermediate certificate and chain.
9. OpenBao imports the signed intermediate, publishes CA and CRL endpoints, and
   issues the replacement service leaf. Ansible installs that leaf without
   exporting either the intermediate key or the service key. After issuance and
   renewal acceptance, the operator removes the retired bootstrap listener key
   from ordinary workstation storage.
10. Exact-pin a dedicated root-generation client certificate, then validate
    scoped administration through an authenticated root-regeneration ceremony
    using that certificate and the external unseal share. Revoke the scoped
    administrator, generated root, and certificate-login tokens before
    revoking the initial root token and removing it from the recovery bundle.
    The legacy unauthenticated root-generation endpoint remains disabled.

The service-foundation and operator-ceremony slices expose
`configure-openbao`, `openbao-status`, `validate-openbao`,
`initialize-openbao`, `unseal-openbao`, `bootstrap-openbao`,
`bootstrap-openbao-pki`, `rotate-openbao-certificate`, and
`retire-openbao-root-token`. Mutation targets require the selected profile,
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
or unseal OpenBao. The redacted
[local service-foundation acceptance record](../evidence/phase-2-openbao-foundation-local-acceptance.md)
captures the completed workstation run.

## Initialize and unseal

Initialization is irreversible for the existing Raft data. Run it once against
the verified uninitialized service:

```sh
RPR_PKI_DIR=/absolute/protected/pki \
PROFILE=workstation-validation \
INCUS_CONFIG_DIR=/absolute/path/to/incus-client \
INCUS_REMOTE=rpr-target \
CONFIRM=initialize-openbao-workstation-validation-rpr-target \
make initialize-openbao
```

The target asks twice for a new recovery-key passphrase. It creates
`RPR_PKI_DIR/openbao-recovery` with mode `0700`, including a
passphrase-protected GPG secret-key export and OpenBao's PGP-encrypted
initialization response. It refuses to overwrite that directory. Back up the
complete directory to two independently recoverable encrypted locations and
keep its passphrase separately.

If OpenBao completes initialization but a later local validation or install
step fails, the workflow deliberately retains the staged encrypted recovery
directory and prints its location. Recover that directory before retrying;
OpenBao cannot be initialized a second time and cleanup must not discard the
only encrypted share.

Then unseal the service:

```sh
RPR_PKI_DIR=/absolute/protected/pki \
PROFILE=workstation-validation \
INCUS_CONFIG_DIR=/absolute/path/to/incus-client \
INCUS_REMOTE=rpr-target \
CONFIRM=unseal-openbao-workstation-validation-rpr-target \
make unseal-openbao
```

The target asks once for the recovery-key passphrase, decrypts the share only
in a process stream, and supplies it to OpenBao over standard input. It is safe
to rerun after a restart: an already-unsealed service returns without reading
the recovery material. The passphrase, share, initial root token, GPG secret-key
export, and protected paths must not be copied into evidence or command logs.

## Audit and recovery checks

The declarative file audit device exists in the server configuration before
routine API configuration. Local acceptance verifies ownership and mode,
rotation with continued writes, and OpenBao's fail-closed response when its only
audit device is unavailable. The failure exercise must restore permissions and
health before any later slice proceeds.

Run the guarded acceptance exercise only against an initialized, unsealed
service:

```sh
PROFILE=workstation-validation \
INCUS_CONFIG_DIR=/absolute/path/to/incus-client \
INCUS_REMOTE=rpr-target \
CONFIRM=accept-openbao-audit-workstation-validation-rpr-target \
make accept-openbao-audit
```

The target sends only denied, unauthenticated requests to a synthetic API path;
it needs no token and reads no audit records. It proves that request and response
entries increase the protected log, forces the installed logrotate policy and
checks continued writes, then temporarily makes the only audit destination
unwritable. The excluded health endpoint must remain healthy while the audited
probe fails closed. A trap restores ownership and mode and signals OpenBao to
reopen the device even if the exercise is interrupted. Final checks require
service health and resumed audit writes.

## Bootstrap KV and scoped policy

After audit acceptance, configure the persistent KV-v2 and policy boundary with
one guarded session:

```sh
RPR_PKI_DIR=/absolute/protected/pki \
PROFILE=workstation-validation \
INCUS_CONFIG_DIR=/absolute/path/to/incus-client \
INCUS_REMOTE=rpr-target \
CONFIRM=bootstrap-openbao-workstation-validation-rpr-target \
make bootstrap-openbao
```

The target asks once for the recovery-key passphrase and decrypts the initial
root token into a mode-`0600` temporary file under the protected operator
runtime directory. A trap removes that plaintext file and the temporary GPG
home on every exit. The token is never accepted through a command argument or
environment variable and every Ansible task that handles it uses `no_log` and
disables diff output.

The initial root token creates only the `rpr-bootstrap-admin` policy and one
non-renewable, orphan bootstrap token with a 15-minute explicit maximum TTL.
That token configures an `rpr-kv/` KV-v2 mount with ten retained versions and
mandatory check-and-set, plus `rpr-operator` and `rpr-machine-read` policies.
The machine policy is read-only under `rpr-kv/data/machines/ci/*`; no machine
credential or authentication method is created in this slice.

Acceptance creates five-minute operator and machine-policy tokens, writes two
synthetic versions with exact CAS, confirms version metadata, and proves the
machine policy is denied on the operator path. An `always` cleanup removes the
synthetic key and revokes all three temporary tokens. Only the empty KV-v2 mount
and three policies persist. The initial root token remains encrypted and active
until recovery-capable administrative access is proven at the end of P2-02.

## Bootstrap the online intermediate

The online-intermediate ceremony is one guarded command even though it crosses
the OpenBao and operator-root trust boundaries:

```sh
RPR_PKI_DIR=/absolute/protected/pki \
PROFILE=workstation-validation \
INCUS_CONFIG_DIR=/absolute/path/to/incus-client \
INCUS_REMOTE=rpr-target \
CONFIRM=bootstrap-openbao-pki-workstation-validation-rpr-target \
make bootstrap-openbao-pki
```

The target asks once for the OpenBao recovery-key passphrase and, when a new
signature is required, once for the offline-root passphrase. It then:

1. creates `pki_int/` with a five-year maximum lease TTL;
2. creates a 15-minute, non-renewable orphan token under the dedicated
   `rpr-pki-bootstrap` policy;
3. generates a named 3072-bit RSA key inside OpenBao and writes only its public
   CSR under `RPR_PKI_DIR/openbao-intermediate`;
4. validates the CSR subject, signature, algorithm, and strength before the
   operator root signs a five-year, path-length-zero intermediate;
5. imports the signed certificate and public root chain back into OpenBao;
6. fixes the named default issuer and publishes its issuing-certificate and
   CRL URLs under `openbao.dev.apadanalab.de`; and
7. fetches the CA, chain, and CRL over authenticated TLS without a token,
   confirms the configured endpoint name through both private BIND
   secondaries, and revokes every temporary bootstrap token.

No intermediate private key crosses the OpenBao API. The protected handoff
directory contains only the CSR, signed certificates, and non-secret resumable
metadata, all mode `0600`; the temporary plaintext initial root-token file is
removed by a trap. A fixed OpenBao key name and the retained CSR allow the same
command to resume after interruption without silently generating another key.
If the issuer is already configured, the command validates and converges its
name, default selection, URLs, and public endpoints without asking for the
offline-root passphrase.

When rebuilding OpenBao against a retained offline root, archive the previous
`root-ca/requests/openbao-online-intermediate.csr` before signing the new
instance's CSR. The ceremony rejects a recorded CSR that differs from its
current OpenBao request. Preserve the root CA database and prior certificate;
the reviewed CA policy permits a new certificate with the same subject.

## Issue and renew the OpenBao listener certificate

Use the same guarded target for the initial replacement and later renewal:

```sh
RPR_PKI_DIR=/absolute/protected/pki \
PROFILE=workstation-validation \
INCUS_CONFIG_DIR=/absolute/path/to/incus-client \
INCUS_REMOTE=rpr-target \
CONFIRM=rotate-openbao-certificate-workstation-validation-rpr-target \
make rotate-openbao-certificate
```

Run it once to replace the operator-root bootstrap leaf, then run the identical
command a second time to exercise renewal. The redacted result identifies the
first operation as `initial online issuance` and the second as `renewal`.
Every invocation deliberately rotates the key and certificate; this is an
explicit mutation, not an idempotent configuration target.

The target creates an exact-name `openbao-listener` issuance role with a
90-day maximum TTL. It permits only `openbao.dev.apadanalab.de`,
`bao-01.dev.apadanalab.de`, and `10.20.0.20`, rejects wildcard and subdomain
issuance, and permits server authentication but not client authentication.
The RSA-3072 leaf key and CSR are generated inside `bao-01`. Only the public CSR
is submitted to `pki_int/sign/openbao-listener`; the API response must not
contain a private key.

Before installation, automation verifies the leaf-to-root chain, all three
subject alternative names, at least 88 days of remaining validity, a changed
serial, and the match between the certificate and the service-local key. It
then installs the leaf plus intermediate chain and asks systemd to reload
OpenBao with `SIGHUP`. This reloads the listener key pair without restarting or
sealing the service. A new TLS connection must present the new leaf, validate
to the offline root, and reach an initialized, unsealed, active health endpoint.

The active pair is copied only to a mode-`0700` staging directory inside the
service before mutation. If signing, installation, reload, or live validation
fails, the issued candidate is revoked when possible, the previous pair is
restored, and OpenBao is reloaded again. Staged keys and rollback copies are
removed on success and ordinary failure. The operator-held bootstrap key is not
deleted automatically; remove its `tls.key` from ordinary workstation storage
only after both accepted runs and independently recoverable offline-root state
have been confirmed. This target uses the initial root only during P2-02
bootstrap. After root retirement, P2-03 must replace that bootstrap
authorization with bounded machine or operator authentication before the next
routine renewal.

## Retire the initial root token

Run this irreversible ceremony only after initial listener issuance and renewal
have both passed:

```sh
RPR_PKI_DIR=/absolute/protected/pki \
PROFILE=workstation-validation \
INCUS_CONFIG_DIR=/absolute/path/to/incus-client \
INCUS_REMOTE=rpr-target \
CONFIRM=retire-openbao-root-token-workstation-validation-rpr-target \
make retire-openbao-root-token
```

The target asks once for the recovery-key passphrase and creates a five-year,
self-signed RSA-3072 client credential in the protected
`openbao-root-generation` directory. Its private key is immediately encrypted
to the existing recovery OpenPGP key. OpenBao exact-pins the leaf certificate;
certificate login produces only a five-minute token with permission to use the
authenticated root-generation endpoints and revoke itself. It cannot generate
a root token without the external Shamir share and grants no KV, PKI, policy,
mount, or token-creation capability.

The ceremony decrypts the client key, Shamir share, and initial root token only
into protected temporary files or process streams. It generates a temporary
root token, creates and exercises a five-minute `rpr-bootstrap-admin` token,
then revokes that administrator and the generated root. Only after those
checks pass does it revoke the certificate-login session and, last, the initial
root. It verifies each revocation, removes `.root_token` from the protected
initialization response atomically, and cleans the temporary material from the
workstation and service container. The encrypted Shamir share remains for
unseal and recovery.

There is no rollback that restores a revoked root token. Back up the complete
recovery directory and root-generation credential together, with the
passphrase held separately. Losing either the exact-pinned client private key
or the Shamir share removes this authenticated recovery path. Replace the
client credential well before its five-year expiry while valid administrative
access still exists. The workflow deliberately does not enable OpenBao's
legacy unauthenticated root-generation endpoint.

Recovery uses a fresh isolated instance with no production DNS alias or client
route. Verify the snapshot checksum, restore it, present the external Shamir
share, and confirm one versioned synthetic KV value plus the non-secret PKI
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
- [File audit device and rotation](https://openbao.org/docs/audit/file/)
- [KV-v2 policy paths](https://openbao.org/docs/secrets/kv/kv-v2/)
- [Token creation](https://openbao.org/docs/commands/token/create/)
- [Intermediate CA setup](https://openbao.org/docs/2.6.x/secrets/pki/quick-start-intermediate-ca/)
- [Operator initialization](https://openbao.org/docs/2.6.x/commands/operator/init/)
- [OpenBao 2.0 mlock removal](https://openbao.org/docs/release-notes/2-0-0/)
