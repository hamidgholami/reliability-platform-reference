# Operator-Managed Root CA Workflow

This is the P2-02 workstation workflow for creating and renewing the internal
root CA and OpenBao bootstrap listener certificate. It deliberately optimizes
for a non-production reference environment: generation happens on the trusted
operator Mac, while encrypted offline backup can follow after validation.

The root key remains human-owned, encrypted, and outside the repository. It is
never copied to OpenBao, Ansible, Incus, CI, or repository state.

## Create the CA and listener certificate

Choose one absolute protected path outside the checkout and run:

```sh
RPR_PKI_DIR=/absolute/protected/pki make openbao-pki-create
```

The target prompts twice for a new root passphrase and then:

- creates an AES-256-encrypted 4096-bit root key and ten-year root certificate;
- initializes the OpenSSL CA database and serial/CRL state;
- creates a 3072-bit OpenBao listener key and one-year certificate;
- fixes the listener SANs to `openbao.dev.apadanalab.de`,
  `bao-01.dev.apadanalab.de`, and `10.20.0.20`;
- generates a one-year CRL;
- applies mode `0700` to protected directories and `0600` to their files; and
- validates the chain, CRL, purpose, lifetime, SANs, modes, and key match.

Creation is staged beside the selected destination and installed only after
validation. It refuses to run if `RPR_PKI_DIR` already exists, so it cannot
silently replace the root or CA database.

The result has this shape:

```text
RPR_PKI_DIR/
├── root-ca/                 # encrypted key, CA database, policy, and CRL
└── openbao-bootstrap/       # ca.crt, ca.crl, tls.crt, and tls.key
```

The passphrase is neither stored nor accepted through an environment variable
or command argument. Losing both the passphrase and recoverable root copy means
creating a new trust hierarchy.

The later `make bootstrap-openbao-pki` ceremony adds
`openbao-intermediate/`. That handoff directory contains only the
OpenBao-generated CSR, signed public chain, and resumable non-secret metadata;
the intermediate private key remains inside OpenBao.

## Validate at any time

```sh
RPR_PKI_DIR=/absolute/protected/pki \
make validate-openbao-bootstrap-tls
```

The output contains only publishable certificate and CRL metadata. Do not
publish the root directory path, listener key, CA database, or passphrase.

## Configure OpenBao

`RPR_PKI_DIR` also supplies the TLS input to the guarded service workflow:

```sh
RPR_PKI_DIR=/absolute/protected/pki \
PROFILE=workstation-validation \
INCUS_CONFIG_DIR=/absolute/path/to/incus-client \
INCUS_REMOTE=rpr-target \
CONFIRM=configure-openbao-workstation-validation-rpr-target \
make configure-openbao
```

Only the root certificate and listener material enter `bao-01`. The encrypted
root key and CA database stay in `root-ca` on the operator side.

## Renew the listener certificate

Before expiry, run:

```sh
RPR_PKI_DIR=/absolute/protected/pki make openbao-pki-renew
```

The target prompts once for the existing root passphrase, verifies the key and
committed policy, creates a new listener key and one-year certificate, refreshes
the CRL, validates the result, and moves the previous listener input under the
protected `archive` directory for rollback. It never replaces the root.

Rerun `configure-openbao` to install the renewed listener material. After the
new certificate is proven in service and rollback is no longer required,
remove the archived listener key through a separately reviewed cleanup action.

Renewal changes the CA database, serial, CRL number, and CRL. Back up the
updated `root-ca` directory after every issuance, renewal, or revocation.

## Backup and optional offline custody

After creation succeeds, copy the complete `root-ca` directory—not merely its
key and certificate—to two independently recoverable encrypted locations.
Verify that each copy can decrypt the key and that the certificate, CA database,
serial files, and CRL are present.

For stronger custody, remove the working `root-ca` directory from the Mac only
after both restore checks pass. Restore it to the same protected layout when a
renewal, revocation, or intermediate-signing operation is needed. The
`openbao-bootstrap` runtime directory may remain on the Mac until OpenBao has
replaced that certificate through its online intermediate.

## Policy and rollback

The committed [`root-ca.cnf`](../../pki/offline-root/root-ca.cnf) and
[`openbao-intermediate-policy.cnf`](../../pki/offline-root/openbao-intermediate-policy.cnf)
are the non-secret issuance policy. CSR-provided extensions are refused, the
intermediate is restricted to path length zero, and the signing wrapper checks
its exact subject, signature, algorithm, strength, and public-key match. The
separate intermediate policy tolerates the ASN.1 string-type difference between
OpenBao's Go-generated CSR and the OpenSSL-generated root without weakening the
bootstrap-listener policy.

If creation fails, its staging directory is removed and no destination is
installed. If renewal cannot install its validated output, the previous
listener directory is restored. A suspected root-key or passphrase compromise
requires replacing the trust hierarchy; deleting a local copy alone does not
repair lost trust.
