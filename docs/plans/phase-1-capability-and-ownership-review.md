# Phase 1 Capability and Ownership Review

- Status: completed
- Review date: 2026-08-28
- Scope revision: 2026-09-04
- Scope: P1-00 of the Phase 1 Incus and network foundation plan
- Runtime mutations: none

Scope note: [ADR-0006](../adr/0006-use-progressive-single-node-delivery.md)
subsequently narrowed Phase 1 to a standalone host and minimal container
substrate. Clustering, BIND/TSIG, and advanced Lima networking findings below
are retained for later milestones and are not current Phase 1 requirements.

## Decision summary

- Lima is the available outer virtualization layer when Incus integration is
  tested on macOS. It is optional because deployment acceptance uses a remote
  Debian VM.
- Native Incus managed bridges, DHCP, DNS forwarding, network zones, IPAM,
  image caching, projects, metrics, snapshots, exports, and clustering are
  sufficient for their Phase 1 requirements.
- Do not add a separate DHCP server, IPAM product, image registry, metrics
  agent, OVN, Ceph, or cluster management product in Phase 1.
- BIND remains justified for the later private-DNS design because the Incus
  network-zone server supports AXFR and NOTIFY but does not answer ordinary
  authoritative queries. It is deferred from Phase 1.
- Ansible owns Debian preparation, upstream hardening integration, Incus
  installation and bootstrap, server-global bootstrap configuration, and guest
  service configuration.
- The pinned official `lxc/incus` provider owns lifecycle-managed Incus API
  resources. Incus owns the generated leases and DNS records derived from those
  resources.
- OpenTofu is the primary IaC command. Terraform runs compatibility validation
  only and is not required to apply the development environment.
- When private DNS is implemented, its TSIG key is a runtime secret consumed by
  both the provider and BIND configuration. It is present in OpenTofu state, so
  that state is secret-bearing.

## Native capability matrix

| Requirement | Native Incus capability | Phase 1 decision | Important boundary |
| --- | --- | --- | --- |
| Linux host | None for macOS host creation | Use remote Debian for acceptance; Lima is optional | Lima is a developer harness, not platform runtime |
| Compute | System containers and QEMU VMs | Require a container smoke test; gate VM tests on nested KVM | Container success does not prove nested VM support |
| Network | Managed bridge, DHCP, DNS, NAT, ACLs, forwards, and tunnels | Use one managed bridge for the standalone profile | Multi-node workload networking is deferred |
| IPAM | DHCP ranges, static addresses, leases, and allocation reporting | Use Incus; add no separate IPAM service | Git owns ranges; Incus owns live allocations |
| DNS | Managed-bridge resolver plus forward/reverse network zones and custom records | Use bridge DNS in Phase 1; retain hidden-primary design for Phase 2 | Network-zone service is AXFR-only, so later BIND closes the query-serving gap |
| Storage | `dir`, ZFS, Btrfs, LVM, Ceph, LINSTOR, and other drivers | Use `dir` for developer validation | It is local and does not support an HA claim |
| Images | Simplestreams/OCI remotes, fingerprinted images, aliases, local cache, and auto-update | Use a fingerprint or reviewed digest for repeatable smoke instances | A moving alias is not reproducible evidence |
| Access | Unix groups, TLS clients, project restrictions, OIDC, OpenFGA, and scriptlets | Use bootstrap TLS with explicit trust in Phase 1 | OIDC without authorization grants full access; identity integration is Phase 2 |
| Metrics | Authenticated OpenMetrics endpoint and metrics-only certificates | Record the endpoint contract; deploy no scraper yet | Prometheus and observability belong to a later phase |
| Backup | Snapshots, instance/volume exports, remote copies, database dumps, and recovery metadata | Test export/import later; keep Borg for off-host orchestration | Same-pool snapshots are not backups; database recovery alone is incomplete |
| Clustering | Cowsql/Raft membership, voter/stand-by roles, groups, and recovery commands | Defer; use one standalone member | A laptop or one cloud provider is not three independent failure domains |

The managed bridge is intentionally limited to the one-member
`single-node-reference` substrate in this phase. Incus requires clustered
networks to be defined on every member, but a plain Linux bridge does not by
itself establish the distributed overlay implied by OVN. Multi-member testing
is therefore deferred until it closes a concrete acceptance gap.

## Dependency decisions

| Component | Gap it closes | Decision | Removal or alternative |
| --- | --- | --- | --- |
| Lima | Runs a disposable native-arm64 Linux VM on macOS | Optional integration feedback | Skip it and use the reference VM when local complexity is not worthwhile |
| Ansible | Prepares hosts and configures services before and after API provisioning | Required | Direct scripts lose role idempotence and inventory contracts |
| `devsec.hardening` | Maintained OS and SSH hardening controls | Required with reviewed overrides | Ansible Lockdown is a later benchmark-specific option |
| OpenTofu | Declarative ownership, plan, drift, and teardown for Incus API resources | Required primary IaC command | Terraform is compatibility-only; direct API automation is more custom code |
| `lxc/incus` provider | Typed lifecycle management for Incus resources | Required | Direct REST/CLI calls require custom state and drift handling |
| AWS provider | Supplies one disposable remote Debian VM for deployment acceptance | Required for the initial reference-host path, in separate state | A pre-existing Debian VM can replace this bootstrap layer |
| BIND 9 | Query-serving authoritative secondaries for Incus AXFR zones | Deferred to the Phase 2 private-DNS milestone | NSD or Knot could replace it behind the same transfer contract |

The following are explicitly excluded from Phase 1:

- a separate router, DHCP server, DNS database, or IPAM product;
- BIND and TSIG until the Phase 2 private-DNS milestone;
- CoreDNS outside its future Kubernetes service-discovery role;
- OVN and Ceph for the laptop profile;
- NetBox, Consul, etcd, or an external Incus cluster manager;
- an internal image registry or custom image-builder pipeline;
- OpenFGA, Keycloak, Vault/OpenBao, Prometheus, and Borg before their phases.

## Supplemental AWS bootstrap review

ADR-0006 added a minimal AWS VM supplier after the original P1-00 review:

- Debian publishes Debian 13 arm64 and amd64 AMIs under official AWS account
  `136693071363`. An owner-, name-, architecture-, EBS-, and HVM-filtered query
  avoids stale regional AMI IDs and paid Marketplace images.
- `t4g.small` supplies 2 vCPU and 2 GiB memory. It is the cheapest test
  hypothesis, not a capacity guarantee; move upward only after a recorded
  resource failure.
- AWS free-tier eligibility differs by account creation date, and the current
  T4g promotion has an end date. Execution must query current eligibility and
  price rather than encode a "free" claim.
- AWS bills public IPv4 outside applicable allowances. The one-host bootstrap
  accepts one temporary address because a NAT gateway adds a much larger fixed
  hourly charge and does not improve this learning objective.
- EC2 Instance Connect Endpoint has no additional endpoint charge and remains a
  future private-access option, but it does not solve required outbound package
  and image access by itself.

The AWS root validates remote-host provisioning and teardown. It does not
simulate a private data center's hypervisor, network appliances, storage, or
failure domains.

## Upstream deployment prior art

The official [`lxc/incus-deploy`](https://github.com/lxc/incus-deploy)
repository is useful prior art for host validation, explicit inventory,
serialized cluster formation, cleanup, and recovery testing. It is not used as
a dependency and its implementation is not copied.

Its reference topology targets a materially different environment: multiple
servers, extra network interfaces, Ceph disks, OVN, and local state directories
for those systems. Phase 1 needs an original, smaller standalone role. Revisit
the upstream project only when implementing a later cluster experiment.

## Provider resource confirmation

Provider release `1.1.1` exposes all resources required by the Phase 1
substrate and the deferred DNS design:

| Desired object | Provider resource | Owner |
| --- | --- | --- |
| Development project and restrictions | `incus_project` | OpenTofu |
| Local `dir` pool | `incus_storage_pool` | OpenTofu |
| Managed bridge | `incus_network` | OpenTofu |
| Root disk and network device contract | `incus_profile` | OpenTofu |
| Phase 1 system container | `incus_instance` | OpenTofu |
| Reviewed cached image, if needed | `incus_image` | OpenTofu |
| Deferred forward and reverse zones | `incus_network_zone` | OpenTofu |
| Deferred manual `A` and `CNAME` records | `incus_network_zone_record` | OpenTofu |

The provider must use an already-reviewed Incus remote and client certificate.
Keep `generate_client_certificates` and `accept_remote_certificate` disabled so
apply cannot silently create client identity or trust a different server.

Ansible owns the Incus API boundary and server-global bootstrap settings needed
before provider execution, including the HTTPS listener. Cluster formation and
the network-zone listener are deferred. The provider does not own package
installation, daemon lifecycle, join tokens, or guest configuration.

## TSIG and state ownership

Incus represents transfer peers as network-zone configuration keys:
`peers.NAME.address` and `peers.NAME.key`. The provider represents the complete
zone configuration as its `config` map. OpenTofu records resource attributes in
state, and local state is plaintext. Therefore, placing the TSIG value in a
`sensitive` input can redact CLI output but cannot keep the value out of state.

The selected ownership model is:

1. The private-DNS milestone uses one protected secret source. Use
   Vault/OpenBao once available; any earlier bootstrap key is synthetic and
   disposable.
2. OpenTofu owns the Incus zone, peer address, and peer key fields.
3. Ansible owns the BIND key file, secondary-zone configuration, and file
   permissions. It consumes the same runtime secret and never reads it from
   OpenTofu output or state.
4. Incus owns generated records. OpenTofu owns reviewed manual records. BIND
   stores only transferred secondary data and must never be edited as primary.

Until an encrypted remote backend is introduced, the implementation must:

- create the state directory with mode `0700` before `tofu init`;
- require state, plans, variable files, and runtime secret files to remain
  ignored by Git and readable only by the operator;
- never print, export, upload, or attach full state or saved plans as evidence;
- pass the TSIG input through a protected runtime path, not command history or
  a committed `.tfvars` file;
- use a synthetic key that protects only the disposable development zone; and
- destroy and remove test state through the documented boundary after evidence
  capture, while retaining any intentionally persistent development state under
  the documented backup and access policy.

This is a deliberate limitation for the later private-DNS milestone. If
secret-bearing plaintext state cannot satisfy that environment's threat model,
migrate the state backend or move the TSIG configuration to a purpose-built
write-only mechanism through a superseding decision.

## Reviewed version baseline

Versions are reviewed as of 2026-08-28. P1-01 will encode them in dependency
files and lock files. Security patch releases require normal dependency review
and are not blocked merely to preserve this table.

| Component | Reviewed version or policy | License posture | Notes |
| --- | --- | --- | --- |
| Debian outer VM | Debian 13 arm64 genericcloud image dated `20260712-2537`, verified by Lima SHA-512 digest | Debian component licenses; image is not vendored | P1-01 records the source and digest used by the YAML |
| Lima | `2.2.0` | Apache-2.0 | Exact developer-harness version |
| Incus | Debian 13 stable `6.0.4-2+deb13u9`, upstream 6.0 LTS line | Apache-2.0 | Install the latest Debian security revision and require identical cluster versions |
| OpenTofu | `1.12.6` | MPL-2.0 | Primary plan/apply command |
| Terraform | `1.15.9` | BUSL-1.1 | Optional compatibility validation only; not redistributed |
| `lxc/incus` provider | `1.1.1` | MPL-2.0 | Exact provider constraint plus generated lock checksums |
| `hashicorp/aws` provider | `6.62.0` | MPL-2.0 | Exact bootstrap-provider constraint plus lock checksums |
| `ansible-core` | `2.21.3` | GPL-3.0-or-later | Supported control Python range includes Python 3.13 |
| `devsec.hardening` | `10.6.0` | Apache-2.0 | Use only `os_hardening` and `ssh_hardening` initially |
| `ansible-lint` | `26.8.0` | GPL-3.0-or-later | Static Ansible validation |
| Molecule | `26.6.0` | MIT | Delegated scenarios target Lima VMs; no container driver required |
| markdownlint-cli2 | `0.23.2` | MIT | Existing repository pin |
| Gitleaks | `8.30.1` | MIT | Existing repository pin |

OpenTofu and Terraform are intentionally tested against the same HCL. OpenTofu
is the maintained no-cost primary path. No HashiCorp binary is bundled in this
repository.

## Lima host and network probe

The repeatable, read-only probe is
[`scripts/lima-host-probe.sh`](../../scripts/lima-host-probe.sh). It emits only
facts required for this harness and excludes serial numbers, hardware UUIDs,
device identifiers, usernames, hostnames, addresses, and unrelated host state.

Observed on 2026-08-28:

| Fact | Result | Consequence |
| --- | --- | --- |
| Host platform | macOS `26.6.2`, arm64 | Native-architecture VZ guest path is applicable |
| Relevant capacity | Apple M4, 32 GB memory | Eligible for optional one-VM Lima integration without making the workstation the platform |
| Lima | `2.2.0`; `vz`, `krunkit`, and `qemu` reported | Use explicit `vmType: vz` rather than relying on the default |
| Debian template | Installed `debian-13` template validates | P1-01 can derive a versioned local YAML |
| Debian arm64 image | Dated image and SHA-512 digest resolve from the template | Preserve the reviewed source and digest in implementation evidence |
| Existing Lima instances | Zero | No pre-existing instance can be confused with project-owned resources |
| Nested virtualization | Host eligible and CLI flag present | `/dev/kvm` and an Incus VM remain runtime-gated tests |
| `socket_vmnet` | Secure-path binary and Lima sudoers absent | Keep it deferred; it is not needed for initial `user-v2` tests |

Official Lima behavior establishes the network contract:

- `vzNAT` gives the macOS host access to a VZ guest address, but does not give
  one guest access to another guest's `vzNAT` address.
- `user-v2` provides VM-to-VM communication and internal
  `lima-NAME.internal` resolution. Direct host routing is not provided; the
  experimental Lima SOCKS tunnel can proxy selected host access.
- `socket_vmnet` can provide host-and-guest reachable addresses, but requires a
  root-owned helper and reviewed sudoers policy. It remains deferred.

The probe proves host eligibility and configuration availability, not nested
KVM execution. Under ADR-0006, Lima and Incus VM checks are optional; Phase 1
deployment acceptance requires a system container on the reference Debian VM.

## P1-00 acceptance record

- Every Phase 1 dependency above closes a named native-Incus or host-platform
  gap.
- Components without a Phase 1 gap are explicitly deferred or removed.
- Host bootstrap, server configuration, provider resources, generated state,
  guest configuration, public DNS, and secondary DNS have non-overlapping
  owners.
- Secret-bearing TSIG fields have one configuration owner, and their state
  exposure has explicit controls and a migration trigger.
- The local host is eligible for the planned Lima paths without recording
  identifying hardware data.

P1-00 is complete. P1-01 is the next work item; it implements repository
interfaces and dependency locks without creating the Incus substrate.

This spike reviewed the provider resource documentation and OpenTofu state
contract without installing an IaC CLI or creating state. The later private-DNS
milestone must inspect a disposable plan and state file before any long-lived
zone or TSIG value is used.

## Primary references

- [Incus managed bridge](https://linuxcontainers.org/incus/docs/main/reference/network_bridge/)
- [Incus IPAM](https://linuxcontainers.org/incus/docs/main/howto/network_ipam/)
- [Incus network zones](https://linuxcontainers.org/incus/docs/main/howto/network_zones/)
- [Incus authentication](https://linuxcontainers.org/incus/docs/main/authentication/)
- [Incus authorization](https://linuxcontainers.org/incus/docs/main/authorization/)
- [Incus metrics](https://linuxcontainers.org/incus/docs/main/metrics/)
- [Incus server backup](https://linuxcontainers.org/incus/docs/main/backup/)
- [Incus clustering](https://linuxcontainers.org/incus/docs/main/explanation/clustering/)
- [Official Incus provider](https://registry.terraform.io/providers/lxc/incus/1.1.1/docs)
- [Official Incus provider release](https://github.com/lxc/terraform-provider-incus/releases/tag/v1.1.1)
- [Official AWS provider release](https://github.com/hashicorp/terraform-provider-aws/releases/tag/v6.62.0)
- [OpenTofu sensitive state](https://opentofu.org/docs/language/state/sensitive-data/)
- [Debian 13 Incus package](https://packages.debian.org/trixie/incus)
- [Lima releases](https://github.com/lima-vm/lima/releases)
- [OpenTofu releases](https://github.com/opentofu/opentofu/releases)
- [Terraform releases](https://releases.hashicorp.com/terraform/)
- [Ansible core releases](https://github.com/ansible/ansible/releases)
- [`devsec.hardening` releases](https://github.com/dev-sec/ansible-collection-hardening/releases)
- [`ansible-lint` releases](https://github.com/ansible/ansible-lint/releases)
- [Molecule releases](https://github.com/ansible/molecule/releases)
- [Debian 13 EC2 images](https://wiki.debian.org/Cloud/AmazonEC2Image/Trixie)
- [AWS EC2 Free Tier eligibility](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html)
- [AWS T4g instances](https://aws.amazon.com/ec2/instance-types/t4/)
- [AWS public IPv4 pricing](https://aws.amazon.com/vpc/pricing/)
- [AWS Budgets pricing](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/)
- [EC2 Instance Connect Endpoint](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-ec2-instance-connect-endpoint.html)
- [Lima Debian 13 template](https://lima-vm.io/docs/templates/)
- [Lima `user-v2` network](https://lima-vm.io/docs/config/network/user-v2/)
- [Lima VMNet networks](https://lima-vm.io/docs/config/network/vmnet/)
- [Lima VZ driver](https://lima-vm.io/docs/config/vmtype/vz/)
