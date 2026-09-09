<!--
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
-->

# Standalone Incus host runbook

P1-03 installs Debian's container-only `incus-base` package and initializes the
daemon as one explicitly non-clustered member. OpenTofu—not this role—will own
storage pools, networks, projects, profiles, images, and system containers in
P1-05.

## Workstation client

The Incus daemon remains on Linux. On the MacBook, install only the supported
Homebrew client before remote administration is enabled:

```shell
brew install incus
incus version
```

The feature-release client can negotiate API extensions with the Debian 6.0
LTS server. Do not install Colima for this project; Lima supplies the optional
local Linux VM. The client is not installed automatically by repository setup.

## Inputs and preflight

Use the same ignored inventory and operator key inputs described in the
[Debian baseline runbook](debian-baseline.md). The P1-02 baseline must already
pass. Then run:

```shell
make preflight-incus
```

The preflight checks Debian 13, the standalone-only input, free root capacity,
synchronized time, kernel namespace support, forwarding, the unused-or-Incus
API port, and an Incus 6.0 LTS candidate from a `debian.org` repository. It does
not update APT metadata or install a package.

## Bootstrap and validation

Use the exact confirmation for the selected profile and inventory hostname:

```shell
export CONFIRM=bootstrap-incus-single-node-reference-incus-reference-01
make bootstrap-incus
make validate-incus
```

The role installs `incus-base`, grants the existing operator `incus-admin`
membership, starts the packaged systemd units, and sends a minimal preseed over
standard input. A versioned Jinja template makes the input reviewable, but it is
rendered in controller memory rather than copied to the host. The preseed
configures only `0.0.0.0:8443`; it creates no file and no provider-owned
resource.

Run both commands a second time. The second bootstrap recap must report zero
changes. Validation checks structured local API data, standalone mode, package
series, services, local HTTPS, and—on the reference profile—TCP reachability
from the controller. It writes an ignored report under `reports/p1-03/` with
the initial server-certificate fingerprint. Trusting that certificate and
creating a client identity belong to P1-05.

## Recovery boundary

Changing `core.https_address` back through `incus config` can close the remote
API without deleting Incus data. Package removal and `/var/lib/incus` deletion
are deliberately not automated because they have different and potentially
destructive consequences. For this disposable Phase 1 host, rebuild the VM
when clean rollback is required.

## Design references

- [Debian `incus-base` package](https://packages.debian.org/trixie/incus-base)
- [Incus macOS client](https://linuxcontainers.org/incus/docs/main/installing/)
- [Initialize Incus with preseed](https://linuxcontainers.org/incus/docs/main/howto/initialize/)
- [Incus daemon readiness](https://linuxcontainers.org/incus/docs/main/reference/manpages/incus/admin/waitready/)
- [Expose the Incus API](https://linuxcontainers.org/incus/docs/main/howto/server_expose/)
