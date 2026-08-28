# Phase 1 Plan: Incus and Network Foundation

- Status: accepted on 2026-08-28; P1-00 is complete and P1-01 is next
- Owner: Hamid Gholami
- Proposed start: approved
- Profile: `developer-validation` first; cluster behavior remains supported and
  separately tested

## Outcome

Create one or three reproducible Debian 13 Linux hosts with Lima, apply minimal
Debian preparation plus a tested upstream hardening profile, and install and
initialize Incus. Then provision and validate the minimum provider-managed
substrate: project, storage, managed network, DNS zones, profiles, and
disposable smoke instances. Prove that the substrate can be rerun, destroyed
within its declared boundary, and recreated without manual instance
configuration.

Phase 1 produces a foundation, not the final platform. It must not deploy
Kubernetes, Vault/OpenBao, Keycloak, Jenkins, artifact services, application
workloads, public ACME automation, Ceph, or OVN.

Lima is test and developer infrastructure. A three-Lima-member cluster validates
automation, membership, and quorum behavior but does not represent three
physical failure domains or justify an HA claim.

## Mandatory design rules

- Apply [ADR-0004](../adr/0004-prefer-native-incus-capabilities.md): investigate
  native Incus functionality before adding an infrastructure dependency.
- Use one explicitly non-HA Incus member for the first developer profile. A
  cluster has at least three members; a two-member mode is invalid.
- Ansible owns host preparation, Incus installation, daemon initialization,
  cluster formation, and guest OS/service configuration.
- A thin local `debian_prepare` role handles only host preparation that upstream
  hardening does not provide. Pin and invoke `devsec.hardening.os_hardening` and
  `devsec.hardening.ssh_hardening` instead of reimplementing their controls.
- Apply an explicit Incus-host variable profile to the upstream roles. Generic
  hardening must not change firewall, forwarding, bridge, namespace,
  filesystem, SSH transport, or AppArmor behavior in a way that breaks Lima or
  Incus; substrate-specific controls belong in `incus_host`.
- The official Incus Terraform/OpenTofu provider owns API-managed projects,
  networks, network zones and records, storage, profiles, and instances.
- Do not split ownership of the same field between Ansible and infrastructure
  state. Resolve sensitive transfer-peer configuration before implementation.
- Terraform/OpenTofu provisioners and `remote-exec` are not configuration
  management.
- All mutations require explicit profile selection. Destruction must print its
  exact boundary and require confirmation.
- No real credentials, client certificates, TSIG keys, state, join tokens, or
  generated inventories enter Git.

## Review gates before implementation

The maintainer must explicitly decide the following in this plan or a linked
ADR before the affected work begins:

| Decision | Recommended starting point | Reason |
| --- | --- | --- |
| First execution target | One Debian 13 Lima VM using VZ | Reproducible developer host with no HA claim |
| Incus release source | Debian 13 native LTS package | Native, supported packaging with minimal repository trust |
| IaC command | OpenTofu apply; Terraform compatibility validation | Open-source primary path while retaining Terraform-compatible HCL |
| Developer storage | `dir` unless a suitable dedicated ZFS device exists | Avoid unsafe loop-device or host-disk assumptions |
| Cluster testing | Three Debian 13 Lima VMs on `user-v2` | VM-to-VM communication without claiming physical HA |
| Lima nested virtualization | Enable and probe on supported M3+ VZ hosts | Incus containers are baseline; Incus VMs remain capability-gated |
| Host-reachable Lima network | Defer `socket_vmnet` pending security review | Needed for direct Mac routing, but adds a privileged host helper |
| Host hardening | Pinned `devsec.hardening` roles plus a thin local preparation role | Reuse maintained controls while testing explicit Incus-safe overrides |
| TSIG ownership | Provider owns Incus peer fields; Ansible owns BIND files; both consume one runtime secret | Prevent overlapping ownership while acknowledging secret-bearing state |

The accepted developer harness uses Lima 2.2 or newer and the tier-one
`debian-13` template. A versioned Lima YAML file disables the unneeded built-in
containerd integration, avoids host-directory mounts into Incus hosts, and sets
explicit CPU, memory, disk, VZ, network, and nested-virtualization inputs.

One-node testing may use `vzNAT` when direct host access is required. The
three-node cluster uses `user-v2`, because `vzNAT` addresses are not reachable
from other guests. `user-v2` provides guest-to-guest communication but not
direct host routing. Full macOS split-DNS acceptance therefore requires a later
choice between securely installed `socket_vmnet`, explicit forwarding, or a
VPN-style route.

## Work items

### P1-00 — Incus capability and ownership spike

- [x] Create a requirement-to-Incus capability matrix for host, network, DNS,
  IPAM, storage, images, access, metrics, backup, and clustering.
- [x] Review current official Incus documentation and `lxc/incus-deploy` as
  upstream prior art; do not copy its implementation.
- [x] Confirm the official provider resources needed for networks, zones,
  records, storage, profiles, and instances.
- [x] Review how network-zone TSIG configuration is represented by the provider
  and OpenTofu state, then select one safe owner for it. Retain an empirical
  disposable plan/state check for P1-05 when the pinned CLI is installed.
- [x] Record pinned Incus, Ansible, provider, IaC CLI, and test-tool versions.
- [x] Verify the Lima Debian 13 template, VZ backend, `user-v2` node-to-node
  network, `vzNAT` host-access boundary, and nested-virtualization probe.
- [x] Capture only non-secret target-host capability facts; never record serial
  numbers, hardware UUIDs, device identifiers, or unrelated host configuration.

Acceptance: every planned dependency either fills a documented Incus gap or is
removed, and every resource or sensitive field has exactly one owner.

Evidence and decisions are recorded in the
[P1-00 capability and ownership review](phase-1-capability-and-ownership-review.md)
and [ADR-0005](../adr/0005-separate-incus-bootstrap-and-resource-ownership.md).

### P1-01 — Repository interfaces and quality gates

- [ ] Add real Ansible collection, inventory, infrastructure, test, and runbook
  files only as they become functional; do not add empty product directories.
- [ ] Add one reusable Lima Debian 13 node YAML and orchestration that creates
  either one standalone node or three consistently named cluster nodes.
- [ ] Extend the root `Makefile` with documented commands for host preflight,
  Lima lifecycle, baseline, bootstrap, plan, apply, validation, and destroy.
- [ ] Pin Ansible collections, including `devsec.hardening`, the Incus provider,
  and CI actions.
- [ ] Add Ansible and HCL formatting, static validation, and secret scanning to
  the existing local/CI interface.
- [ ] Document which checks run on a laptop and which require disposable Linux
  infrastructure.

Acceptance: a reviewer discovers every supported command through `make help`,
and static CI needs no infrastructure credentials.

### P1-02 — Debian preparation and upstream hardening integration

- [ ] Pin a reviewed `devsec.hardening` release and record its supported Ansible
  and Debian versions, license, changelog, and selected roles.
- [ ] Add a thin `debian_prepare` role that validates Debian 13 and manages only
  security/package updates, approved prerequisite packages, CA certificates,
  Python readiness, time synchronization, the operator account, sudo, SSH
  authorized keys, persistent journal policy, and reboot-required reporting.
- [ ] Invoke `devsec.hardening.os_hardening` and
  `devsec.hardening.ssh_hardening` directly; do not copy, fork, or lightly
  rewrite their tasks into this repository.
- [ ] Define a reviewed Incus-host variable profile that preserves required
  IPv4 and selected IPv6 forwarding, namespaces, filesystems, kernel features,
  AppArmor integration, Lima's SSH user, and required SSH forwarding behavior.
- [ ] Leave generic firewall ownership out until an Incus-compatible policy is
  selected and tested against Incus-managed `nftables`, DHCP, DNS, and NAT.
- [ ] Validate the generated SSH configuration before reload, open a fresh
  control connection after hardening, reboot, and reconnect before continuing.
- [ ] Verify clock health before Incus joins and report unexpected listening
  services as evidence.
- [ ] Run preparation and both upstream roles twice, then capture forwarding,
  namespace, AppArmor, SSH, and reboot-readiness evidence for integration.
- [ ] Make no CIS compliance claim; reserve benchmark-specific remediation for
  a separately reviewed optional profile.

Acceptance: preparation and pinned upstream roles are idempotent, SSH checks
prevent lockout, required updates and host prerequisites are covered, and the
reviewed profile does not break Lima access, Incus forwarding, namespaces,
AppArmor, or managed bridge services.

### P1-03 — Original `incus_host` Ansible role

- [ ] Validate supported OS/release, package source, stable member addresses,
  time synchronization, required ports, storage inputs, virtualization support,
  version compatibility, and member count before mutation.
- [ ] Install the selected Incus package and manage daemon readiness.
- [ ] Support explicit `standalone` and `cluster` modes, rejecting two members.
- [ ] Render and apply versioned `incus admin init --preseed` input without
  persisting secret-bearing artifacts.
- [ ] Bootstrap exactly one cluster member and serialize additional joins using
  short-lived tokens protected by `no_log`.
- [ ] Delete join/preseed artifacts unconditionally, including after failure.
- [ ] Verify daemon/API health and cluster membership through structured output,
  not human-oriented text matching.
- [ ] Stop at the healthy Incus API boundary; do not create provider-owned
  projects, networks, storage, profiles, or instances in this role.

Acceptance: a second run is idempotent, no join material remains, standalone and
three-member modes report healthy, and a failed preflight makes no mutation.

### P1-04 — Lima role integration and recovery tests

- [ ] Create one standalone Debian 13 Lima VM from the versioned YAML and apply
  `debian_prepare`, the pinned upstream hardening roles, and then `incus_host`.
- [ ] Create three Debian 13 Lima VMs on `user-v2`, apply preparation and the
  upstream hardening profile, and test bootstrap plus serialized Incus joins.
- [ ] Probe `/dev/kvm` and an Incus VM smoke test only when Lima nested
  virtualization is enabled and the guest kernel reports support.
- [ ] Treat an Incus system container with working DHCP, DNS, NAT, and outbound
  connectivity as the mandatory nested workload for the Lima acceptance path.
- [ ] Test invalid two-member input, incompatible versions, failed joins, token
  cleanup, rerun behavior, and safe recovery entry points.
- [ ] Document that nested tests prove automation behavior, not physical failure
  domains or production HA.

Acceptance: test evidence shows idempotence and cleanup on both success and
failure without publishing credentials or host-identifying data.

### P1-05 — Provider-managed Incus substrate

- [ ] Configure the pinned official `lxc/incus` provider without auto-generated
  long-lived credentials.
- [ ] Inspect a disposable plan and state file with a synthetic TSIG value to
  confirm representation and redaction before creating the persistent zone.
- [ ] Create the development project and its limits/restrictions.
- [ ] Create the `platform0` managed bridge with `10.20.0.0/24`, NAT, DHCP,
  non-overlapping stable/dynamic/MetalLB ranges, and IPv6 policy.
- [ ] Create forward and reverse Incus network zones and attach them to the
  network.
- [ ] Create the selected storage pool and minimal instance profile.
- [ ] Create one disposable system container and one VM only when host
  virtualization capability permits.
- [ ] Export a non-secret machine-readable inventory for later Ansible stages.
- [ ] Keep initial state on a protected local filesystem, ignored by Git, with
  operator-only permissions and no state or saved-plan publication. Document
  backup and later encrypted-backend migration paths.

Acceptance: plan/apply is deterministic, a second apply has no drift, address
ranges match the approved plan, and provider-owned resources can be destroyed
without uninstalling or de-initializing Incus.

### P1-06 — Private DNS serving path

- [ ] Prove automatic forward/reverse records for Incus-managed instances.
- [ ] Provision two minimal BIND instances with stable Incus reservations.
- [ ] Configure both as authoritative secondaries of the Incus hidden primary.
- [ ] Let the provider own Incus transfer-peer fields while Ansible owns BIND
  key files; supply both from the same protected runtime TSIG source. Verify
  AXFR, NOTIFY, SOA serial, refresh, and expiry behavior.
- [ ] Configure Incus managed-bridge DNS and Kubernetes's future forwarding
  contract without deploying Kubernetes early.
- [ ] Add a macOS split-DNS and `10.20.0.0/24` routing runbook; DNS success must
  not be confused with network reachability.
- [ ] Test automatic instance records plus one reviewed manual `A` record and
  one `CNAME` applied through the Incus API.
- [ ] Stop either BIND instance and temporarily stop the hidden primary while
  recording the observed resolution behavior.

Acceptance: trusted clients resolve the private zone through either BIND
secondary, public Netcup DNS contains no RFC 1918 records, and Incus remains the
record authority.

### P1-07 — Baseline guest configuration

- [ ] Generate Ansible inventory from provider outputs without embedding
  secrets or fixed addresses in application configuration.
- [ ] Apply `debian_prepare` and the pinned upstream hardening roles with a
  service-guest variable profile, preserving the same safety and idempotence
  contract used on Incus hosts.
- [ ] Configure BIND through a narrowly scoped role; do not add unrelated
  platform services.
- [ ] Verify that a workload-cluster outage cannot remove the Phase 1 DNS
  serving path.

Acceptance: guests are configured without Terraform/OpenTofu provisioners, and
rerunning Ansible reports no unintended changes.

### P1-08 — Operator workflows, teardown, and evidence

- [ ] Provide explicit `preflight`, `bootstrap-incus`, `plan`, `apply`,
  `validate`, and `destroy` Make targets.
- [ ] Require profile selection and show the target host/project/resource
  boundary before apply or destroy.
- [ ] Verify clean rebuild from the documented bootstrap inputs.
- [ ] Publish redacted evidence for role idempotence, provider no-drift,
  instance/container health, DNS resolution, failure tests, and teardown.
- [ ] Record duration, host requirements, known limitations, and cleanup state.

Acceptance: an operator can create, validate, destroy, and recreate the Phase 1
substrate using documented commands, and the final cleanup check finds no
orphaned instances, volumes, networks, zone records, state copies, or join
artifacts inside the declared test boundary.

## Implementation order

```text
Capability/Lima network review
        |
        v
Debian 13 Lima VM(s)
        |
        v
Debian preparation + upstream hardening + lockout test
        |
        v
incus_host role + standalone tests
        |
        v
cluster-mode tests
        |
        v
official provider substrate
        |
        v
Incus zones -> BIND secondaries -> split DNS
        |
        v
guest baseline + destroy/recreate evidence
```

Each arrow is a review gate. Do not start the next block while the previous
block has unresolved ownership, secret-handling, or recovery failures.

## Verification interface

The exact targets are implemented during P1-01, but the intended public
interface is:

```sh
make doctor
make check
make lima-up NODES=1
make preflight PROFILE=developer-validation
make baseline PROFILE=developer-validation
make bootstrap-incus PROFILE=developer-validation
make plan PROFILE=developer-validation
make apply PROFILE=developer-validation
make validate PROFILE=developer-validation
make destroy PROFILE=developer-validation
make lima-down NODES=1
```

Apply and destroy remain interactive by default. CI runs static validation and
disposable integration tests; it does not mutate the maintainer's persistent
Incus environment.

## Rollback boundaries

- Before Incus initialization, the role may remove only packages and files it
  created and must preserve unrelated host configuration.
- Lima teardown targets only explicitly named project instances and preserves
  unrelated Lima VMs, networks, cached images, and host configuration.
- After initialization, uninstalling Incus or removing a cluster member is a
  separate explicit recovery operation, never an automatic rollback.
- Provider destroy removes only provider-owned Phase 1 resources in the selected
  project. It must not remove Incus itself, unrelated projects, shared images,
  or protected state backups.
- DNS rollback removes manual records and transfer configuration in dependency
  order while preserving the public Netcup zone.
- Any destructive cluster, storage, or state recovery procedure requires a
  dedicated runbook and explicit human confirmation.

## Phase 1 exit criteria

Phase 1 is complete only when:

- the maintainer accepts all review-gate decisions;
- native Incus capabilities are used unless a documented gap justifies another
  component;
- one- and three-node Lima harnesses are reproducible from the reviewed YAML;
- Debian preparation and pinned upstream hardening are idempotent,
  lockout-safe, and Incus-compatible;
- standalone and three-member automation contracts pass at their declared test
  level, with no two-member topology;
- the role and guest configuration are idempotent and leave no secret artifacts;
- official-provider apply is repeatable and reports no unexplained drift;
- Incus-generated and manual DNS records resolve through either BIND secondary;
- failure, teardown, and clean-rebuild evidence is reviewed;
- local and required remote CI checks pass; and
- no Phase 2 identity, secrets, or PKI implementation starts early.

## Maintainer review checklist

- [x] Accept the recommended starting gates.
- [x] Use Debian 13 Lima VMs as the first execution targets.
- [x] Use the Debian-native Incus LTS package policy initially.
- [x] Use OpenTofu for apply and validate Terraform compatibility.
- [x] Use `dir` storage unless the host review identifies a suitable ZFS device.
- [x] Use three Lima VMs for disposable cluster-contract testing.
- [x] Accept the `user-v2`/`vzNAT` split and later host-network review.
- [x] Use pinned `devsec.hardening` roles with a thin `debian_prepare` role and
  explicit Incus-safety overrides.
- [x] Accept the provider/Ansible TSIG boundary and protected local state
  controls recorded by P1-00.
- [x] Accept the work-item order and Phase 1 exit criteria.
