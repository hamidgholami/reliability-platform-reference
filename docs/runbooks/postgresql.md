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

## Boundary and recovery

The Incus bridge ACL limits routed ingress but does not filter peer traffic
on the same bridge. Before changing PostgreSQL to listen on its private
address, install an internal CA signed server certificate and explicit
`pg_hba.conf` entries for the OpenBao admin and current smoke client addresses.
Do not expose TCP 5432 publicly.

If the guest setup fails, leave the listener local and rerun after correcting
the cause. Local peer access can inspect or repair the synthetic database.
The provider destroy target removes this stateful container and its data;
use it only for a disposable environment with the required recovery material
retained. Rebuilding a permanent instance needs a separate migration plan.
