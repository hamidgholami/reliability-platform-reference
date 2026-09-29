# P2-03 PostgreSQL service

The provider owns the bounded `pg-01` container at `10.20.0.21` and its
private DNS name. Debian 13 supplies PostgreSQL 17 from stable/security.
Ansible owns the guest installation and database configuration. The first
configuration step keeps the listener on localhost with TLS off while the
signed server certificate and OpenBao bootstrap credential are prepared.

## Local preparation

After reviewing and applying the substrate plan, run `make validate` to
regenerate the ignored inventory. Review the selected profile, remote,
address, and the current `smoke-01` lease. Then run from the repository root:

```sh
export PROFILE=workstation-validation
export INCUS_CONFIG_DIR="$PWD/.cache/incus/opentofu"
export INCUS_REMOTE=rpr-target

CONFIRM=configure-postgresql-workstation-validation-rpr-target \
  make configure-postgresql
```

The target installs Debian's `postgresql-17` and client packages, creates
`rpr_p203.public.probe` with one synthetic row, and checks the installed
version and local-only settings. It uses local peer access as the `postgres`
operating-system account. It creates no remote login or application password.
The command can be rerun after a partial package or service failure.
After the signed listener certificate is installed, this local-only setup
target refuses to run so it cannot close the live private endpoint.

## Enable and accept dynamic credentials

Use the same protected `RPR_PKI_DIR` established by the OpenBao foundation.
Unseal OpenBao after a Lima restart, then verify its health with
`make openbao-status`. The command below prompts for the recovery-key
passphrase only in the operator terminal:

```sh
export RPR_PKI_DIR=/absolute/protected/pki
export PROFILE=workstation-validation
export INCUS_CONFIG_DIR="$PWD/.cache/incus/opentofu"
export INCUS_REMOTE=rpr-target

CONFIRM=enable-postgresql-dynamic-workstation-validation-rpr-target \
  make enable-postgresql-dynamic
CONFIRM=accept-postgresql-dynamic-workstation-validation-rpr-target \
  make accept-postgresql-dynamic
```

The first target creates a server key and CSR inside `pg-01`, a one-use
database administrator password in protected guest runtime storage, and
limited PostgreSQL roles. Authenticated OpenBao root recovery installs an
exact PostgreSQL signing role, signs the public CSR, and configures one
database secrets engine connection and a single `rpr-p203-read` role. The
temporary root and recovery tokens are revoked before the signed public
certificate and CA bundle are installed in `pg-01`. Ansible then enables
TLS on its private address and restricts `pg_hba.conf` to `bao-01` and the
current Incus-reported `smoke-01` address. The bootstrap password transfer
files are removed even if the command fails. OpenBao retains its encrypted
connection credential; PostgreSQL retains only its password hash.

The second target logs in with the exact-pinned machine certificate, requests
one short-lived credential, reads the synthetic row over verified TLS, and
checks that revocation and expiry prevent another login. It prints only
redacted acceptance fields. The OpenBao database role has a 30-second
default lease and a five-minute maximum.

## Boundary and recovery

The Incus bridge ACL limits routed ingress but does not filter peer traffic
on the same bridge. Before changing PostgreSQL to listen on its private
address, install an internal CA signed server certificate and explicit
`pg_hba.conf` entries for the OpenBao admin and current smoke client addresses.
Do not expose TCP 5432 publicly.

The OpenBao administrator is a PostgreSQL `CREATEROLE` account. That privilege
is broader than one database, so this demonstration uses its own bounded
container and permits only one OpenBao dynamic role. It has no PostgreSQL
superuser or file access role. Local peer access by the `postgres` operating
system account is the recovery path.

If the guest setup fails, leave the listener local and rerun after correcting
the cause. Local peer access can inspect or repair the synthetic database.
If signed certificate installation or OpenBao connection verification fails,
fix the cause and rerun the guarded enable target with a new recovery session.
The PostgreSQL admin password is reset through local peer access on each run;
its old OpenBao copy is replaced. A healthy dynamic-credential acceptance is
required before treating the service as ready. If OpenBao Raft state is lost,
reset this administrator password via local peer access and repeat the setup.
The provider destroy target removes this stateful container and its data;
use it only for a disposable environment with the required recovery material
retained. Rebuilding a permanent instance needs a separate migration plan.
