# Offline Root CA Ceremony

This procedure creates or recovers the human-owned internal root CA and issues
the short-lived bootstrap listener certificate required by P2-02. Run the root
steps on a deliberately offline device. The private root key, its passphrase,
the CA database, and their storage paths are never repository or platform
inputs.

The committed [`root-ca.cnf`](../../pki/offline-root/root-ca.cnf) is policy, not
custody automation. It fixes the allowed OpenBao listener identities, refuses
CSR-provided extensions, permits only one path-length-zero intermediate below
the root, and uses SHA-384 signatures. Review it from a signed repository
revision before transferring it to the offline environment.

## Fixed lifetimes and names

| Artifact | Lifetime | Required identity or constraint |
| --- | --- | --- |
| Offline root | 10 years | `ApadanaLab Offline Root CA`, CA path length 1 |
| Root CRL | 30 days | Signed by the offline root |
| Bootstrap listener | 30 days | TLS server only; the two private DNS names and `10.20.0.20` |
| Future online intermediate | Set during the later PKI slice | CA path length 0; private key generated inside OpenBao |

Thirty days is long enough for the bounded bootstrap and short enough that the
temporary listener certificate cannot silently become permanent. Stop if the
bootstrap cannot finish within that window; issue a new leaf rather than
extending the existing one.

## 1. Prepare the connected workstation request

Use a protected directory outside the checkout. The listener key is
intentionally unencrypted because the OpenBao service must start unattended;
its filesystem mode and short lifetime are the compensating controls.

```sh
umask 077
export RPR_OPENBAO_TLS_DIR=/absolute/protected/openbao-bootstrap
export RPR_OPENBAO_CSR_DIR=/absolute/protected/csr-transfer
install -d -m 0700 "$RPR_OPENBAO_TLS_DIR" "$RPR_OPENBAO_CSR_DIR"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 \
  -out "$RPR_OPENBAO_TLS_DIR/tls.key"
chmod 0600 "$RPR_OPENBAO_TLS_DIR/tls.key"

openssl req -new -sha384 \
  -key "$RPR_OPENBAO_TLS_DIR/tls.key" \
  -subj '/O=ApadanaLab/OU=Platform Services/CN=openbao.dev.apadanalab.de' \
  -out "$RPR_OPENBAO_CSR_DIR/openbao-bootstrap.csr"

openssl req -in "$RPR_OPENBAO_CSR_DIR/openbao-bootstrap.csr" \
  -noout -verify -subject
openssl dgst -sha256 "$RPR_OPENBAO_CSR_DIR/openbao-bootstrap.csr"
```

Transfer only `openbao-bootstrap.csr` and the reviewed `root-ca.cnf` to the
offline device. Compare their SHA-256 digests through a separate trusted
channel before signing. The listener private key never enters the offline-root
kit or removable transfer media.

## 2. Create or recover the offline root

For a new root, initialize an empty protected CA database. Choose a strong root
passphrase interactively; do not put it in an environment variable, command
argument, script, terminal recording, or ordinary password manager export.

```sh
umask 077
export RPR_ROOT_CA_DIR=/absolute/offline/apadanalab-root-ca
install -d -m 0700 \
  "$RPR_ROOT_CA_DIR" \
  "$RPR_ROOT_CA_DIR/certs" \
  "$RPR_ROOT_CA_DIR/crl" \
  "$RPR_ROOT_CA_DIR/newcerts" \
  "$RPR_ROOT_CA_DIR/private" \
  "$RPR_ROOT_CA_DIR/incoming" \
  "$RPR_ROOT_CA_DIR/outgoing"
install -m 0600 /trusted/transfer/root-ca.cnf \
  "$RPR_ROOT_CA_DIR/root-ca.cnf"
touch "$RPR_ROOT_CA_DIR/index.txt"
printf '1000\n' >"$RPR_ROOT_CA_DIR/serial"
printf '1000\n' >"$RPR_ROOT_CA_DIR/crlnumber"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 \
  -aes-256-cbc -out "$RPR_ROOT_CA_DIR/private/root-ca.key"
chmod 0600 "$RPR_ROOT_CA_DIR/private/root-ca.key"

cd "$RPR_ROOT_CA_DIR"
openssl req -config root-ca.cnf -new -x509 -days 3650 -sha384 \
  -extensions root_ca_extensions \
  -key private/root-ca.key \
  -subj '/O=ApadanaLab/OU=Platform Trust/CN=ApadanaLab Offline Root CA' \
  -out certs/root-ca.crt
```

For an existing root, restore the entire CA directory—not only the key and
certificate—and verify its backup checksum before continuing. Recreating
`index.txt`, serial state, or CRL numbering would break revocation history.

## 3. Inspect and sign the bootstrap request

Place the transported CSR at `incoming/openbao-bootstrap.csr`. Review its
signature, subject, and public-key size. The CA policy supplies the SANs and
does not copy unreviewed CSR extensions.

```sh
cd "$RPR_ROOT_CA_DIR"
openssl req -in incoming/openbao-bootstrap.csr \
  -noout -verify -subject -text

openssl ca -config root-ca.cnf \
  -extensions openbao_bootstrap_server \
  -days 30 -notext -md sha384 \
  -in incoming/openbao-bootstrap.csr \
  -out outgoing/tls.crt

openssl ca -config root-ca.cnf -gencrl \
  -out crl/root-ca.crl

install -m 0600 certs/root-ca.crt outgoing/ca.crt
install -m 0600 crl/root-ca.crl outgoing/ca.crl
```

Do not use `-batch` for the real signing ceremony: the two OpenSSL confirmation
prompts are intentional human review gates. Transfer only `ca.crt`, `ca.crl`,
and `tls.crt` back to the connected workstation and verify transfer digests
through the separate trusted channel.

## 4. Assemble and validate the runtime input

Install the returned public artifacts beside the listener key. Although the
CRL is public, mode `0600` keeps the entire one-use transfer directory under a
single simple protection rule.

```sh
install -m 0600 /trusted/return/ca.crt "$RPR_OPENBAO_TLS_DIR/ca.crt"
install -m 0600 /trusted/return/ca.crl "$RPR_OPENBAO_TLS_DIR/ca.crl"
install -m 0600 /trusted/return/tls.crt "$RPR_OPENBAO_TLS_DIR/tls.crt"

OPENBAO_TLS_INPUT_DIR="$RPR_OPENBAO_TLS_DIR" \
make validate-openbao-bootstrap-tls
```

The validation checks the root and CRL signatures, current revocation state,
remaining lifetime, TLS-server purpose, exact SANs, key match, and modes. Its
output contains only publishable certificate and CRL metadata.

## Custody, backup, and rollback

Before using the root, make two independently recoverable encrypted copies of
the complete CA directory. Hold the passphrase separately and record custodians,
media identifiers, root fingerprint, CRL number, and next-update time without
recording private paths or secrets. Prove one restore on an isolated offline
device before describing the copies as recoverable.

If inspection or validation fails, do not edit an issued certificate. Revoke
it from the offline CA database, generate a new CRL, destroy the connected
listener key and certificate, and begin again with a fresh key and CSR. If the
root key or passphrase may be exposed, stop platform bootstrap and replace the
root; deleting local files alone does not repair lost trust.
