# Phase 1 Plan: Minimal Single-Node Incus Foundation

- Status: revised and accepted on 2026-09-04; P1-00 through P1-05 complete,
  P1-06 active
- Owner: Hamid Gholami
- Default deployment profile: `single-node-reference`, supplied initially by
  the AWS bootstrap root
- Optional test profile: `workstation-validation`

## Outcome

Create or select one Debian 13 VM, install and initialize standalone Incus, and
use the official Incus provider to create the smallest useful substrate:

- one restricted development project;
- one local `dir` storage pool;
- one Incus-managed bridge with DHCP, DNS, and NAT;
- one minimal instance profile; and
- one disposable system container.

Prove host and provider idempotence, container connectivity, bounded destroy,
and clean recreation. This is the first deployable platform increment, not a
production or HA environment.

The AWS bootstrap path starts with a `t4g.small` instance and a 30 GiB encrypted
`gp3` root volume. This is a deliberately small hypothesis, not a capacity
claim: record observed usage and move to `t4g.medium` or larger only when the
active acceptance test demonstrates a resource failure. A pre-existing local
or hosted VM may satisfy the same target contract. Incus system containers are
the only Phase 1 guest type; nested virtualization and Incus VMs are deferred.

Phase 1 does not deploy Kubernetes, DNS secondaries, PKI, Vault/OpenBao,
Keycloak, Jenkins, artifact services, observability, backup services, Ceph, OVN,
or application workloads. AWS is used only to supply the single generic Debian
target; AWS-native platform architecture remains a later phase.

## Delivery principle

Apply [ADR-0006](../adr/0006-use-progressive-single-node-delivery.md). Every
work item must produce executable evidence before scope expands. Planning or
research that is not required by the active acceptance criterion moves to the
backlog.

Use this promotion ladder:

| Level | Purpose | Required environment |
| --- | --- | --- |
| Workstation checks | Formatting, linting, syntax, unit tests, and non-mutating IaC validation | macOS and CI |
| Disposable integration | Optional fast feedback for Ansible and Incus behavior | One Lima Debian VM |
| Deployment acceptance | Real package, SSH, reboot, Incus, provider, and rebuild evidence | One `single-node-reference` Debian VM, initially EC2 |
| Expansion tests | Cloud-provider behavior, clustering, and failure domains | Later, requirement-specific infrastructure |

Passing workstation checks does not prove target behavior. Conversely, a Lima
test is skipped when it requires privileged macOS networking or substantial
Lima-specific engineering; the same test runs on the reference VM instead.
The `single-node-reference` contract is normative: shared OpenTofu and Ansible
configuration must remain runnable against a generic remote Debian target.
Lima-only details belong at the workstation profile boundary and must never
weaken, reshape, or delay the reference-environment implementation.

The [end-to-end execution milestones](../runbooks/end-to-end-milestones.md)
define the mandatory reality checks and human handoffs. P1-02 and P1-03 trigger
the host-foundation integration checkpoint. Completion of P1-06 triggers one
full create, configure, validate, destroy, recreate, and final-cleanup session.
Before any paid run, stop and give the operator a current, step-by-step account,
credential, cost, expiry, execution, and cleanup checklist.

The workstation runs the pinned Ansible toolchain from a repository-local
Python virtual environment. Standard Ansible SSH is the Phase 1 execution path.
Mitogen is not a default dependency: this phase manages one host, most elapsed
time is expected inside package and image operations, and Mitogen currently
depends on the third-party strategy-plugin interface deprecated by Ansible.
Reconsider it only after a multi-node benchmark identifies controller transport
as a meaningful bottleneck.

Broad Ansible tags are also deferred. They are useful in large operational
playbooks when measured workflows need safe subsets, but this phase has small,
ordered playbooks whose preflight, access protection, and validation must not be
skipped. Explicit playbooks and Make targets are the supported boundaries; add
only narrowly justified tags later, with safety tests.

## Mandatory design rules

- Apply [ADR-0004](../adr/0004-prefer-native-incus-capabilities.md): use native
  Incus functionality unless a documented gap justifies another service.
- Use one explicitly non-HA Incus member. Do not implement cluster joins in
  Phase 1.
- Ansible owns Debian preparation, hardening integration, Incus installation,
  standalone initialization, and guest configuration.
- A thin local `debian_prepare` role handles only preparation that the pinned
  `devsec.hardening` roles do not provide.
- Apply explicit Incus-safe hardening overrides. Do not break forwarding,
  namespaces, AppArmor, bridge services, or the operator's SSH route.
- The official Incus Terraform/OpenTofu provider owns projects, networks,
  storage, profiles, and instances after the Incus API is healthy.
- Terraform/OpenTofu provisioners and `remote-exec` are not configuration
  management.
- AWS VM bootstrap and Incus substrate use separate OpenTofu roots and state.
- All mutations require explicit profile selection. Apply and destroy show the
  exact host, project, and resource boundary and remain interactive by default.
- No credentials, private keys, client certificates, state, plans, or generated
  inventories enter Git or published evidence.
- AWS resources require owner, purpose, environment, and expiry tags. No NAT
  gateway, load balancer, Elastic IP, or paid Marketplace image belongs in the
  minimum path.

## Accepted starting gates

| Decision | Phase 1 choice |
| --- | --- |
| Deployment target | One Debian 13 VM; AWS bootstrap is the initial supplier |
| Starting AWS resources | `t4g.small` plus 30 GiB encrypted `gp3`; scale from evidence |
| AMI | Latest official Debian 13 arm64 from owner `136693071363`; no paid image subscription |
| Workload type | Incus system containers only; Incus VMs deferred |
| Incus release source | Debian 13 native `incus-base` 6.0 LTS policy; security patch updates allowed |
| IaC command | OpenTofu apply; Terraform compatibility validation |
| Storage | Local `dir` pool |
| Host hardening | Pinned `devsec.hardening` roles plus thin local preparation |
| Local virtualization | One disposable Lima VM when useful, never mandatory |
| AWS region | `eu-central-1` by default; configurable and included in cost checks |
| AWS networking | Dedicated minimal VPC path; one temporary public IPv4, no NAT gateway or Elastic IP |
| Clustering | Deferred; not a Phase 1 exit criterion |
| Private authoritative DNS | Deferred to Phase 2 beside PKI and identity |

## Minimal AWS VM contract

The AWS configuration is a separate bootstrap root. It creates only:

- one dedicated VPC, public subnet, internet gateway, route table, and route
  association;
- one security group allowing SSH and the Incus API only from a required
  operator CIDR;
- one EC2 key-pair resource from a supplied public key;
- one `t4g.small` EC2 instance using the current official Debian 13 arm64 AMI;
  and
- one encrypted, delete-on-termination, 30 GiB `gp3` root volume.

The instance requires IMDSv2, uses basic rather than paid detailed monitoring,
and runs on demand for predictable short tests. Spot instances and additional
AWS services are not part of the first path.

Resolve the latest AMI using an `aws_ami` data source restricted to Debian's
official AWS account `136693071363`, the `debian-13-arm64-*` name, arm64
architecture, EBS root device, and HVM virtualization. Do not hard-code a
region-specific AMI ID or select an unreviewed Marketplace image. The Debian
image has no paid software subscription, but EC2, EBS, public IPv4, and data
transfer can still cost money.

The default uses a temporary auto-assigned public IPv4 because the host needs
outbound package and image downloads and the workstation must reach SSH and the
Incus API. A public IPv4 is billable outside applicable free-tier allowances.
Do not add a NAT gateway merely to make the address private: its fixed hourly
and processing charges would make this one-host path more expensive. A later
private-access profile may use an EC2 Instance Connect Endpoint plus a reviewed
egress design.

Before apply, the workflow must:

- verify AWS caller identity, selected region, current instance price, and AMI
  architecture; query the account-plan status when available and otherwise
  assume no Free Tier discount;
- verify an active notification-only AWS cost budget; its subscriber address
  remains outside this repository;
- require an explicit operator CIDR and reject `0.0.0.0/0`;
- show every potentially billable resource and an expiry timestamp;
- require an explicit confirmation; and
- make `aws-destroy` and an orphan check part of the same session's workflow.

Free-tier and promotions reduce charges but never become correctness
assumptions. The current cheapest eligible type can change, and `t4g.small` may
prove too small. The repository keeps the type configurable and records the
tested value in evidence.

## Work items

### P1-00 — Capability and ownership review

Status: complete.

The original investigation remains in the
[P1-00 capability and ownership review](phase-1-capability-and-ownership-review.md).
[ADR-0006](../adr/0006-use-progressive-single-node-delivery.md) narrows which
reviewed capabilities are required now. Research into clustering, BIND/TSIG,
and advanced Lima networking is retained as future context, not implementation
work.

### P1-01 — Repository interfaces and fast quality gates

- [x] Add only the Ansible, inventory, infrastructure, test, and runbook files
  needed by the single-node increment; do not create empty future directories.
- [x] Pin Ansible, `devsec.hardening`, OpenTofu, the Incus provider, test tools,
  the AWS provider, and CI actions in their normal dependency or lock files.
- [x] Add Ansible formatting, syntax, and lint checks plus HCL formatting and
  non-mutating validation to the local and CI interface.
- [x] Add a sanitized example inventory for one remote Debian VM.
- [x] Add an isolated AWS bootstrap root matching the minimal AWS VM contract;
  keep its backend and outputs separate from Incus-substrate state.
- [x] Add one reusable Lima Debian 13 YAML and lifecycle wrapper, but keep Lima
  targets optional.
- [x] Extend `make help` with clear local-check, optional-Lima, target
  preflight, baseline, bootstrap, plan, apply, validate, and destroy commands.
- [x] Document which commands are workstation-only and which mutate a selected
  Linux target.

Acceptance: static CI uses no infrastructure credentials, `make help` exposes
every supported command, and no command silently creates a VM or cloud resource.

### P1-02 — Minimal Debian preparation and hardening

- [x] Validate Debian 13 before mutation.
- [x] Add a thin `debian_prepare` role for required updates, approved packages,
  CA certificates, Python, time synchronization, the operator account, sudo,
  authorized keys, persistent journal policy, and reboot reporting.
- [x] Invoke pinned `devsec.hardening.os_hardening` and
  `devsec.hardening.ssh_hardening`; do not copy their implementation.
- [x] Define only the Incus-safe overrides needed to preserve forwarding,
  namespaces, filesystems, AppArmor, and the active SSH transport.
- [x] Validate generated SSH configuration and a new control connection before
  closing the original session.
- [x] Reboot when required, reconnect, and run the preparation and hardening
  path twice.
- [x] Record unexpected listening services and relevant post-run facts without
  collecting unrelated host information.

Acceptance: the second run is idempotent, SSH remains reachable after reboot,
and the host is ready for Incus. No CIS or production-hardening claim is made.

Deployment evidence on 2026-09-10 used Debian 13.6 on ARM64. Debian requested
no reboot, fresh authenticated SSH reconnection passed, the final baseline run
reported zero changes, and validation found only TCP 22 exposed.

### P1-03 — Standalone `incus_host` Ansible role

- [x] Validate OS/release, stable target address, time health, package source,
  storage inputs, and required ports before mutation.
- [x] Install the selected Debian Incus package and manage daemon readiness.
- [x] Support standalone mode only and reject cluster-mode input with a clear
  deferred-scope message.
- [x] Render and apply versioned `incus admin init --preseed` input without
  persisting generated artifacts.
- [x] Verify daemon and API health through structured output.
- [x] Stop at the healthy API boundary; do not create provider-owned projects,
  networks, storage pools, profiles, or instances.
- [x] Run twice and verify that no bootstrap artifact remains.

Acceptance: standalone initialization is idempotent, the Incus API is healthy,
and failed preflight makes no mutation.

Deployment evidence on 2026-09-10 used Debian's `incus-base` 6.0.4 package.
The second bootstrap and repeated validator each reported zero changes. The
standalone API, packaged systemd units, controller reachability, and non-root
SSH operator access passed. Only TCP 22 and 8443 were exposed. API-derived
counts found no storage pool, managed network, instance, non-default project,
or non-default profile, and a host check found no persisted preseed artifact.

### P1-04 — Reference VM bootstrap and promotion

- [x] Implement the guarded AWS plan, apply, inventory, destroy, and orphan
  workflow with offline safety tests.
- [x] Run all fast workstation checks first.
- [x] Add an ignored inventory generator that consumes Lima's runtime SSH
  configuration, proves loopback-only access, and records Ansible task timing.
- [x] When useful, create one disposable Debian 13 Lima VM and exercise P1-02
  and P1-03 without adding privileged host networking.
- [x] Skip Lima cleanly when unavailable or when the test would require
  Mac-specific routing work.
- [x] Execute the AWS bootstrap plan and show identity, region, selected official
  AMI, instance type, disk, public IPv4, estimated price, tags, and expiry.
- [x] Apply the AWS root only after explicit confirmation and generate a
  non-secret target inventory from its outputs.
- [x] Apply the same P1-02 and P1-03 paths to the selected
  `single-node-reference` VM.
- [x] Confirm resource capacity, reboot/reconnect behavior, Incus API access,
  and absence of unintended listeners on the reference VM.

Acceptance: the real reference VM, not merely mocks or Lima, reaches the
healthy standalone Incus API boundary. The AWS root has no resources outside
its declared boundary. Optional Lima failure does not block deployment when the
reference-target tests pass.

The AWS reference VM passed this acceptance on 2026-09-10. Lima was initially
skipped because the real Debian target already exercised the required host
boundary. The minimum disk-capacity gate, baseline reconnection, Incus
controller and operator access, listener allowlist, and second-run convergence
all passed. OpenTofu then destroyed all 11 bootstrap resources and left empty
state. Direct EC2 API checks confirmed the instance terminated and its volume,
network, and access resources absent. AWS's tagging index still returned
recently deleted ARNs immediately afterward, so the final clean orphan-check
proof remains a P1-06 requirement. Final authoritative substrate acceptance
will use a new short-lived reference VM during the P1-06 end-to-end run.

The optional Lima replay passed on 2026-09-15 with Debian 13.7 on ARM64 and
Incus 6.0.4. Baseline and bootstrap second runs reported zero changes. SSH
reconnection, AppArmor, time synchronization, namespaces, standalone API
health, and non-root operator access passed through unprivileged loopback
forwarding. Only the expected SSH and Incus API listeners were exposed, and
the API confirmed zero provider-owned resources before P1-05.

### P1-05 — Minimal provider-managed substrate

The first implementation slice configures the provider to consume an isolated,
pre-enrolled client identity. `incus-client-check` and `plan` verify trust and
standalone topology before any mutation. The resource slice enables apply only
for a saved, digest-verified, non-destructive plan with an exact confirmation;
validation and provider-only destroy have separate boundaries.

- [x] Pin and configure the official `lxc/incus` provider against an explicitly
  trusted remote; disable automatic client-certificate generation and automatic
  server-certificate acceptance.
- [x] Install or validate the macOS Incus client and configure separate,
  explicitly trusted identities for the human operator and OpenTofu.
- [x] Create the development project and only the restrictions needed now.
- [x] Create a local `dir` storage pool.
- [x] Create the `platform0` managed bridge with configurable `10.20.0.0/24`,
  NAT, DHCP, Incus DNS, and a documented IPv6 policy.
- [x] Create one minimal profile and one disposable system container; do not
  install VM-only host dependencies or create an Incus VM.
- [x] Keep the container image reference configurable and document the
  image-change replacement or rollout path for stateful services.
- [x] Verify container DHCP, name resolution, outbound connectivity, and
  structured health information.
- [x] Prove `incus list`, `incus info`, and operation inspection from the
  MacBook without bypassing OpenTofu ownership for routine mutations.
- [x] Export only a non-secret machine-readable inventory for later Ansible.
- [x] Keep state on an ignored operator-only local path and never publish state
  or saved plans as evidence.
- [x] Apply twice and explain or eliminate all drift.

P1-05 acceptance passed on the optional Lima environment on 2026-09-15 with
Incus 6.0.4. The provider created the five-resource boundary; internal DNS,
external DNS, NAT, project restrictions, and the IPv6 policy passed runtime
validation. A second plan and apply reported no changes. Provider-only destroy
then removed all five resources and left empty managed state while Incus and
both client trust paths remained healthy. Clean recreation created all five
resources again, `smoke-01` received `10.20.0.147`, runtime validation passed,
and the final plan and apply reported no changes. Authoritative
`single-node-reference` acceptance remains part of P1-06.

Acceptance: the provider creates a working container deterministically, the
second apply has no unexplained drift, and provider destroy does not uninstall
or de-initialize Incus.

### P1-06 — Operator workflow, teardown, and evidence

- [x] Implement the public `preflight`, `baseline`, `bootstrap-incus`, `plan`,
  `apply`, `validate`, and `destroy` Make targets.
- [x] Implement distinct `aws-plan`, `aws-apply`, `aws-destroy`, and
  `aws-orphan-check` targets so VM lifecycle cannot be confused with Incus
  resource lifecycle.
- [x] Require `PROFILE=single-node-reference` and show the exact boundary before
  each mutation.
- [ ] Verify clean rebuild from documented inputs after provider destroy.
- [ ] Publish redacted evidence for hardening idempotence, Incus health,
  provider no-drift, container connectivity, destroy, and recreation.
- [ ] Record duration, peak observed resource use, limitations, and final
  cleanup state.

Acceptance: another operator can create, validate, destroy, and recreate the
minimal foundation with the documented commands and no orphaned
provider-managed resources.

## Deferred backlog

- Benchmark standard Ansible SSH against Mitogen only when a multi-node profile
  demonstrates that controller transport, rather than remote work, is a
  material part of elapsed time.

These are valid target capabilities, but none blocks Phase 1:

- three-member Incus clustering, quorum, join-token, and recovery tests;
- BIND secondaries, Incus network zones, TSIG, split DNS, and friendly external
  service names;
- `socket_vmnet`, direct macOS routing, and persistent local hosting;
- Incus VM tests and nested-virtualization tuning;
- Ceph, OVN, HA storage/networking, and physical failure-domain claims; and
- broader cloud networking, managed services, and provider-specific platform
  topology beyond the single EC2 bootstrap host.

Private DNS moves to Phase 2 because it should be implemented together with the
internal CA, certificates, identity, and secret delivery. Clustering is added
only when a later test has real independent failure domains or a specific
cluster-automation learning objective.

## Implementation order

```text
Fast workstation checks
        |
        v
Minimal Debian preparation + hardening
        |
        v
Standalone Incus role
        |
        +--> optional one-VM Lima feedback
        |
        v
AWS plan/apply -> single reference Debian VM acceptance
        |
        v
Minimal provider substrate + one container
        |
        v
Destroy/recreate evidence -> Phase 1 complete
```

Do not begin a later block while the current acceptance test fails. Do not add
a deferred component merely because its future design is already documented.

## Verification interface

P1-01 establishes this interface. P1-02 and P1-03 have enabled their host
commands; commands for later work items still fail closed and identify their
phase:

```sh
make doctor
make check
make test-local
make lima-up                 # optional
make lima-inventory          # optional; running Lima VM only
make lima-start              # optional; existing stopped Lima VM only
make aws-plan PROFILE=single-node-reference
make aws-apply PROFILE=single-node-reference
make preflight               # explicit inventory, target, and public key
make baseline-check          # explicit inventory, target, and public key
make baseline                # same inputs plus exact confirmation
make validate-baseline       # writes ignored local evidence
make preflight-incus         # read-only host and package-source gates
make bootstrap-incus         # same inputs plus exact confirmation
make validate-incus          # structured health and ignored evidence
make plan PROFILE=single-node-reference
make apply PROFILE=single-node-reference
make validate PROFILE=single-node-reference
make destroy PROFILE=single-node-reference
make aws-destroy PROFILE=single-node-reference
make aws-orphan-check PROFILE=single-node-reference
make lima-delete             # optional and explicitly confirmed
```

Static CI performs no infrastructure mutation. Target integration requires
explicit inventory and credentials supplied outside Git. Apply and destroy are
interactive by default.

## Rollback boundaries

- Before Incus initialization, Ansible may remove only files and packages it
  created and must preserve unrelated host configuration.
- Lima teardown targets only the explicitly named disposable project VM.
- Incus uninstall or de-initialization is a separate manual recovery action,
  never part of provider destroy.
- Provider destroy removes only resources in the selected Phase 1 project and
  preserves Incus, unrelated projects, and protected state backups.
- AWS bootstrap destroy removes only the dedicated VPC, network, key-pair,
  instance, and storage resources declared by that root. It runs only after
  Incus-substrate destroy and preserves unrelated account resources.
- A pre-existing reference VM remains outside this repository's destruction
  boundary.

## Phase 1 exit criteria

Phase 1 is complete only when:

- all fast local and CI checks pass;
- the selected Debian 13 reference VM meets the documented starting contract;
- the AWS bootstrap path resolves an official Debian image, passes its cost and
  exposure gates, and leaves no orphan after final destroy;
- preparation and hardening are idempotent and SSH-safe;
- standalone Incus bootstrap is idempotent and healthy;
- provider apply creates the minimal project, storage, bridge, profile, and
  system container with no unexplained second-apply drift;
- the container demonstrates DHCP, DNS, NAT, and outbound connectivity;
- bounded destroy and clean recreation pass;
- runtime, resource usage, limitations, and redacted evidence are recorded; and
- no deferred DNS, clustering, broader cloud architecture, Kubernetes, or Phase
  2 service begins early.

## Maintainer decisions

- [x] Use the workstation primarily for fast checks and optional disposable
  integration.
- [x] Use one Debian 13 VM as the default deployment target.
- [x] Include a separate minimal AWS OpenTofu root to supply that VM initially.
- [x] Start AWS with `t4g.small` and 30 GiB encrypted `gp3`, then scale only
  from measured failure.
- [x] Use the official Debian 13 arm64 AMI and never depend on a paid image.
- [x] Accept a temporary restricted public IPv4 instead of a NAT gateway for
  the cheapest straightforward bootstrap path.
- [x] Use system containers only in Phase 1 and defer Incus VMs.
- [x] Remove three-member clustering from the Phase 1 exit path.
- [x] Move private authoritative DNS and TSIG beside PKI and identity in Phase
  2.
- [x] Finish the minimal apply/destroy/recreate slice before expanding scope.

## References

- [Debian 13 EC2 images](https://wiki.debian.org/Cloud/AmazonEC2Image/Trixie)
- [AWS EC2 Free Tier eligibility](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html)
- [AWS T4g specifications and current promotion](https://aws.amazon.com/ec2/instance-types/t4/)
- [AWS public IPv4 pricing](https://aws.amazon.com/vpc/pricing/)
- [AWS Budgets pricing](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/)
- [EC2 Instance Connect Endpoint](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-ec2-instance-connect-endpoint.html)
