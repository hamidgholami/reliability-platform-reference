# P2-03 disposable SSH certificate target

`ssh-test-01` is a disposable Debian 13 container at `10.20.0.221` in the
restricted `rpr-dev` project. Its Incus-generated private DNS name is
`ssh-test-01.dev.apadanalab.de`. The `ssh-certificate-test` bridge ACL
restricts routed TCP 22 ingress to the platform CIDR. Incus 6.0 does not
reliably load that default-project ACL directly on this project's NIC, and
bridge ACLs do not filter same-bridge peers. The target SSH daemon must
therefore accept only the configured Ed25519 certificate CA and one test
principal; password and bare public-key login stay disabled.

The target has one CPU, 256 MiB memory, and a 2 GiB disk cap. It is separate
from the stateful PostgreSQL and OpenBao services. The fixture is absent by
default. Set `SSH_TEST_ENABLED=true` on `make plan`, `make apply`, and
`make validate` to create it for acceptance. Review the saved OpenTofu plan
for only the SSH target, profile, ACL, and bridge update before applying it.
Validation regenerates the ignored inventory and checks its address through
both private DNS secondaries.

The OpenBao SSH CA private key remains inside encrypted Raft storage. Only
its `ssh-ed25519` public key goes to the target. The temporary client key
and target host key use Ed25519. A short-lived certificate fixes one
non-sudo test account as its principal and carries no forwarding extension.
After `make validate` regenerates the inventory, use the protected OpenBao
recovery directory from P2-02. Unseal OpenBao if the Lima VM restarted. Run
these commands from the repository root, entering the recovery passphrase
only in the operator terminal:

```sh
export RPR_PKI_DIR=/absolute/protected/pki
export PROFILE=workstation-validation
export INCUS_CONFIG_DIR="$PWD/.cache/incus/opentofu"
export INCUS_REMOTE=rpr-target

CONFIRM=configure-ssh-certificates-workstation-validation-rpr-target \
  make configure-ssh-certificates
CONFIRM=accept-ssh-certificates-workstation-validation-rpr-target \
  make accept-ssh-certificates
```

The first target uses authenticated root recovery to create one Ed25519 SSH
CA inside OpenBao and one signing role. It revokes the temporary root and
recovery tokens before configuring `ssh-test-01`. The target installs only
the public CA, keeps one Ed25519 host key, and runs a certificate-only
daemon for the non-sudo `rpr-probe` account. The role accepts only Ed25519
client keys, fixes the principal to `rpr-probe`, sets a five-minute maximum
certificate lifetime, and provides no forwarding extension.

The acceptance target creates a temporary Ed25519 client key inside
`smoke-01`, pins the target's Ed25519 host key, and signs a 30-second
certificate through the machine identity. It checks allowed login, wrong
principal, excessive TTL, forbidden forwarding extension, and expiry. The
machine token is revoked and the temporary client key and certificate are
removed even if a probe fails. It prints only redacted results.

If the signing ceremony fails, inspect the failed step and rerun with a new
protected recovery session. The wrapper reuses an existing Ed25519 CA and
reconciles the role; it refuses an existing non-Ed25519 CA. If target
configuration fails, the OpenBao role may already exist, but the target
daemon is stopped until its certificate policy is installed. Rerun after
correcting the cause.

After acceptance, retire the fixture in two provider plans. Incus will not
delete an ACL still attached to a bridge. First, detach the ACL and remove
the target and profile while retaining the ACL. Then delete the detached ACL:

```sh
SSH_TEST_ACL_RETAINED=true RETIRE_SSH_TEST=1 make plan
SSH_TEST_ACL_RETAINED=true \
  CONFIRM=apply-incus-workstation-validation-rpr-target make apply
RETIRE_SSH_TEST=1 make plan
CONFIRM=apply-incus-workstation-validation-rpr-target make apply
make validate
make plan
```

Review each saved plan before applying it. The retirement guard accepts only
the SSH instance, profile, and ACL deletions and the exact ACL detachment on
the bridge. The final plan must have no managed-resource changes. The
OpenBao SSH CA and signing role remain available for future acceptance; retire
them through authenticated recovery when SSH certificate issuance is no
longer a requirement.
