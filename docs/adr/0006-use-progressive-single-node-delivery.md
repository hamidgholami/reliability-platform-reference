# ADR-0006: Use progressive single-node delivery

- Status: accepted
- Date: 2026-09-04
- Decider: Hamid Gholami

## Context

The complete reference architecture contains enough products and failure-mode
work to become documentation-heavy before it produces a usable system. Incus
also requires Linux, while the maintainer's MacBook is best suited to editing,
static checks, and short-lived test workloads rather than hosting the reference
platform continuously.

Phase 1 previously made one- and three-node Lima environments, cluster
contracts, BIND secondaries, TSIG, and macOS split networking part of one exit
path. Those are individually useful experiments, but together they delay the
first working foundation.

## Decision

Deliver the platform as small vertical increments. The first deployable
increment is one standalone Incus host on a Debian 13 VM. A small, isolated
OpenTofu root creates that VM on AWS; this supplies a generic remote Linux
target and is not presented as an on-premises network simulation. A
pre-existing VM can implement the same logical profile later.

The AWS path starts with `t4g.small` and a 30 GiB encrypted `gp3` root volume,
then scales only if measured integration tests fail for lack of capacity. It
resolves the latest official Debian 13 arm64 AMI with an owner-verified query
instead of pinning a regional AMI ID. Free-tier or promotional eligibility is
checked at execution time and is never assumed. Incus system containers are the
only Phase 1 guest type, so nested virtualization and Incus VMs are deferred.

Use this promotion path:

1. Run formatting, linting, syntax checks, unit tests, and non-mutating IaC
   validation directly on the workstation and in CI.
2. Use one disposable Lima Debian VM only when it provides useful integration
   feedback without privileged networking or substantial platform-specific
   work.
3. Create or select the `single-node-reference` Debian VM and perform deployment
   acceptance there.
4. Add broader cloud-platform and multi-node tests only for a later requirement.

Lima is optional test infrastructure, not the primary platform. AWS bootstrap
state is separate from Incus-substrate state so destroying one layer has an
explicit boundary. If a test requires extensive macOS routing,
`socket_vmnet`, or Lima-only workarounds, run it on the reference VM instead.

Phase 1 ends after Ansible configures the host, Incus runs standalone, the
official provider creates a minimal project/storage/network/profile/container
substrate, and the documented destroy/recreate path passes. Three-member Incus,
BIND/TSIG private DNS, macOS split DNS, and Incus VM testing are deferred beyond
that milestone. Private authoritative DNS moves beside PKI and identity in
Phase 2; cluster behavior remains a later optional failure-domain experiment.

## Consequences

- Each phase must finish with executable evidence before expanding scope.
- The workstation catches inexpensive failures but cannot prove Linux package,
  SSH, reboot, networking, or Incus behavior.
- The Ansible and Incus layers remain reusable beyond the AWS bootstrap and
  make no HA claim.
- EC2 validates a remote-host workflow but does not reproduce a private data
  center's hypervisor, switching, firewall, storage, or failure domains.
- The minimal VM cannot run every future platform service simultaneously.
  Later phases add one coherent workflow at a time and record measured resource
  needs.
- Some previously researched Phase 1 capabilities remain useful backlog items
  but are no longer prerequisites for the first foundation.

## Validation and reversal

Phase 1 must produce a clean apply, second-run idempotence, a working Incus
system container, safe destroy, and clean recreation on the reference VM. Track
time and resource consumption. Expand the default topology only when a later
acceptance criterion cannot be demonstrated on one node.

Supersede this ADR if measured constraints show that the single-node target
cannot support even the active vertical slice.
