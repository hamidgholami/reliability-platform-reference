# P2-03 Machine Authentication

This slice gives the existing `smoke-01` container one synthetic machine
identity. It can request only the planned dynamic PostgreSQL credential and
SSH client certificate. Those engines are configured in the following P2-03
slices; this first slice proves certificate login and policy capabilities.
The redacted [local acceptance record](../evidence/phase-2-machine-auth-local-acceptance.md)
captures the workstation result.

## Boundary and custody

| Material | Location and owner | Retirement |
| --- | --- | --- |
| Root-generation client key and Shamir share | Existing protected operator recovery kit outside Git | Used only for the guarded ceremony; temporary plaintext files are removed |
| Generated root token | OpenBao root-generation ceremony | Revoked before the configuration token is released |
| Machine client key | `/etc/rpr-machine-auth/client.key` inside `smoke-01`, mode `0600` | Replace with the disposable instance; never copy it to the controller or OpenBao |
| Machine client certificate | Same directory; public copy exact-pinned in OpenBao | Replace its pin before the 90-day certificate expires; remove the role when the test client is retired |
| Machine login token | In Ansible process memory for the acceptance probe | Revoked after capability checks; the explicit lifetime cap is five minutes |

The existing `cert` auth mount is reused. The root-generation certificate has
only root-generation rights. The new `rpr-p203-machine` role has no default or
KV policy and is pinned to the `smoke-01` leaf certificate. A human does not
use the machine credential.

`smoke-01` routes the private `dev.apadanalab.de` zone to the two BIND
secondaries at `10.20.0.10` and `10.20.0.11`. Other names retain the Incus
bridge resolver at `10.20.0.1`. The playbook persists this split DNS setting
with systemd-networkd and systemd-resolved before the recovery ceremony.

## Prepare and run

From the repository, use the protected recovery directory already established
by P2-02. The inventory must have been regenerated with `make validate` after
the current provider state was applied. Unseal OpenBao after a host restart;
the target checks service health before asking for the recovery passphrase.
Review the selected profile, remote, and private service address before running
the mutating target:

```sh
export RPR_PKI_DIR=/absolute/protected/pki
export PROFILE=workstation-validation
export INCUS_CONFIG_DIR="$PWD/.cache/incus/opentofu"
export INCUS_REMOTE=rpr-target

CONFIRM=configure-machine-auth-workstation-validation-rpr-target \
  make configure-machine-auth
```

The target first creates a 90-day Ed25519 X.509 client key and certificate
inside `smoke-01`. It then prompts locally for the recovery-key passphrase,
streams the decrypted single Shamir share and places the root-generation
client key in a protected temporary file, then generates a temporary root
token through authenticated
root generation. That root writes the fixed machine policy and exact certificate
pin, then is revoked before the playbook checks a five-minute machine login and
exact capabilities. The acceptance login token is revoked. The client private
key and Shamir share never enter Git, OpenTofu state, Ansible logs, or command
arguments.

Run the same target again only with a new guarded recovery session. The guest
key and certificate remain unchanged. A certificate with fewer than seven days
remaining fails closed so the disposable machine identity can be deliberately
replaced.

## Failure and removal

On ordinary failure, the wrapper removes local and remote plaintext ceremony
files. The recovery helper attempts to revoke any generated root token in its
cleanup. If revocation fails, inspect OpenBao audit and token state before
retrying. A failed run may leave the machine policy or exact-pinned role
installed; re-running after correcting the cause reconciles these objects.

To retire this synthetic identity, first disable or delete the named
`rpr-p203-machine` cert role, revoke outstanding machine tokens, then remove
`smoke-01` through the existing provider lifecycle. A clean environment
recreation generates a new key and pin. Do not delete the root-generation
recovery credential or offline-root material as part of this test cleanup.
