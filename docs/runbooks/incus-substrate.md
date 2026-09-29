<!--
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
-->

# Incus substrate lifecycle

This runbook manages the Phase 1 substrate plus the provider-owned P2-01 private
DNS, P2-02 OpenBao, and P2-03 PostgreSQL and SSH resources after the host and client trust
checks pass. The same OpenTofu root targets a remote Debian reference VM or the
optional Lima rehearsal. Lima does not change the resource contract.

## Managed boundary

The provider owns exactly twenty-one resources:

- restricted project `rpr-dev`, limited to six containers and no VMs;
- host-wide local `dir` pool `rpr-local`;
- host-wide managed bridge `platform0`;
- project profiles `system-container`, `dns-secondary`, `secrets-service`,
  `database-service`, and `ssh-test-service`;
- forward and IPv4 reverse network zones;
- the manual `resolver` record and `openbao` service alias;
- host-wide network ACLs `openbao-api`, `postgresql-tls`, and
  `ssh-certificate-test`;
- disposable Debian system container `smoke-01`;
- authoritative secondary containers `dns-01` and `dns-02`;
- bounded OpenBao service container `bao-01`; and
- bounded PostgreSQL service container `pg-01`; and
- disposable SSH certificate target `ssh-test-01`.

The project has isolated profiles and storage volumes but shared images.
Network access is limited to `platform0`. The profile explicitly places its
root disk on `rpr-local`, while aggregate and per-pool limits bound disk usage
to 18 GiB. This is compatible with the Incus 6.0 LTS API: its later maintenance
releases support per-pool limits but not the newer
`restricted.storage-pools.access` key. Phase 1 creates no other storage pool.
The project also caps aggregate CPU at six and memory at 2304 MiB. The system
profile allows one CPU and 512 MiB memory. Containers remain unprivileged and
nesting is disabled.

The bridge defaults to `10.20.0.0/24`, uses `.1` as its gateway and DNS
forwarder, and leases `.120` through `.219`. Incus supplies bridge DHCP, DNS,
firewalling, and outbound IPv4 NAT. IPv6 is explicitly disabled for Phase 1.
The private suffix defaults to `dev.apadanalab.de`.
The DNS service containers use stable addresses `.10` and `.11`, one CPU,
256 MiB memory, and 2 GiB disk each.

The OpenBao foundation uses `bao-01` at `.20`, one CPU, 512 MiB memory, and a
4 GiB disk. The `openbao` alias points to the instance's Incus-generated DNS
name. PostgreSQL uses `pg-01` at `.21` with the same CPU, memory, and disk caps.
The disposable SSH target uses `.221`, one CPU, 256 MiB memory, and a 2 GiB
disk. Three Incus ACLs are assigned to the shared bridge for routed ingress
to TCP 8200, 5432, and 22 from the platform CIDR. Ordinary NICs retain
explicit allow defaults; the three service NICs reject unmatched ingress.
This assignment avoids
an Incus 6.0 cross-project ACL loading bug when a NIC in `rpr-dev` directly
names an ACL owned by the shared network's `default` project. Incus bridge
ACLs do not filter traffic between peers on the same bridge; OpenBao policy,
PostgreSQL TLS, `pg_hba.conf`, and the SSH daemon provide those service
boundaries. This layer
does not install OpenBao or PostgreSQL or create TLS, PKI, seal, or application
secrets. Those steps are described in the
[OpenBao foundation](openbao-foundation.md) and
[PostgreSQL](postgresql.md) runbooks.

## Inputs and plan

First export the client trust inputs from the
[trust runbook](incus-client-trust.md). Optional non-secret overrides are:

```sh
export INCUS_IPV4_CIDR=10.20.0.0/24
export INCUS_DNS_DOMAIN=dev.apadanalab.de
export INCUS_IMAGE=images:debian/13
```

The CIDR must be a canonical RFC 1918 `/24`. Verify it does not overlap the
target host, LAN, VPN, VPC, or another Incus network. Then create a saved plan:

```sh
CONFIRM=generate-private-dns-tsig-workstation-validation \
  make private-dns-secrets
make incus-client-check
make plan
```

The wrapper verifies the required Incus API extensions and nftables firewall
driver, then refuses a create/update plan containing any delete action. It
writes runtime variables, state, plan, and plan metadata below ignored
`.cache/incus-substrate` with operator-only permissions. Review the displayed
resource boundary before applying it. The disposable SSH target, profile, and
ACL are created only when `SSH_TEST_ENABLED=true`. The TSIG file and provider
state are secret-bearing even though plans and outputs do not display the values.

## Apply and validate

For the optional workstation profile, apply the exact saved plan with:

```sh
CONFIRM=apply-incus-workstation-validation-rpr-target make apply
```

Use the confirmation printed by `make plan` for another profile or remote.
The apply generates the guest inventories. Configure both BIND secondaries as
described in the [private-DNS runbook](private-dns.md), then run `make validate`.
Validation checks project restrictions, the pool, bridge NAT and IPv6 policy,
profiles, running containers, stable and DHCP addresses, zone ownership,
the service ACLs and names through both authoritative secondaries, internal and
external DNS, and outbound IPv4 connectivity. It writes ignored structured
evidence plus substrate, private-DNS, and OpenBao inventories.

Prove convergence with a fresh plan:

```sh
make plan
```

The second plan must contain no managed-resource changes.
Runtime acceptance on Lima is useful evidence but does not replace the final
`single-node-reference` execution on a real remote VM.

## Image changes

`INCUS_IMAGE` is configurable, but changing an existing instance image can
require replacement. The normal plan command rejects that destruction. For
the disposable Phase 1 smoke container, use the provider destroy workflow,
change the alias, and create the substrate again. Do not use this method for a
stateful service.

Later stateful services require an explicit rollout design: create a second
instance, configure and validate it, migrate or restore its data, switch the
service endpoint, and remove the old instance only after rollback is safe.

## Provider-only teardown

Destroy never uninstalls or de-initializes the Incus server:

```sh
CONFIRM=destroy-incus-workstation-validation-rpr-target make destroy
```

The wrapper displays and applies an OpenTofu destroy plan for its twenty-one managed
resources, then asserts that no managed resource remains in its local state.
Do this only for a disposable environment before removing its outer VM. It
deletes PostgreSQL and OpenBao data; retain verified recovery material before
any teardown. Client certificate revocation
is a separate operator action described in the trust runbook.
