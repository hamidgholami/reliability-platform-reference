<!--
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
-->

# End-to-end execution milestones

Static checks cannot prove package installation, SSH reconnection, reboot
behavior, Incus networking, or cloud cleanup. This project therefore has
explicit reality checkpoints. A checkpoint passes only after its commands run
against the named environment and its evidence is reviewed.

## Milestone A — Continuous workstation checks

Run `make check` after every implementation slice and in CI. This milestone is
free and non-mutating. It validates syntax, lint, secret and license policy,
OpenTofu configuration, mocked AWS safety rules, and command safety guards.

Passing Milestone A never establishes runtime correctness.

## Milestone B — Host-foundation integration

Trigger: P1-02 and P1-03 automation are implemented.

Status: passed on 2026-09-10 against the AWS-supplied Debian 13 reference VM.
The final baseline, Incus bootstrap, and Incus validation runs reported zero
changes. No persisted preseed, unexpected exposed listener, or provider-owned
Incus resource was found. OpenTofu then destroyed all 11 AWS bootstrap resources
and left empty state. Direct EC2 API checks found the instance terminated and
its volume, network, and access resources absent. The AWS tagging index still
returned recently deleted ARNs immediately afterward, so Milestone C must use a
new short-lived VM and obtain a clean final orphan-check result.

Use one disposable Debian 13 VM. Try the existing one-VM Lima profile first
when it can faithfully exercise system containers, SSH restart, and reboot. If
Lima needs special macOS networking or hides relevant target behavior, stop
adapting the project to Lima and use the temporary AWS reference VM instead.
The workstation-validation path derives an ignored inventory from Lima's own
SSH configuration and uses an unprivileged loopback forward for the Incus API;
it does not require a routable guest address.

The checkpoint must prove:

1. Debian preflight rejects invalid input without mutation.
2. Baseline apply, SSH replacement, reboot, and reconnection succeed.
3. A second baseline run reports no change.
4. Incus preflight, package installation, stdin preseed, and API health succeed.
5. A second Incus bootstrap reports no change.
6. No preseed artifact, unexpected listener, or provider-owned Incus resource
   is created.

Before a paid AWS run, pause and tell Hamid exactly what to prepare. At minimum
this includes account access with MFA, a least-privilege AWS CLI profile,
billing visibility and a small notification budget, the current public `/32`
operator address, a dedicated SSH key pair, region and expiry choices,
estimated billable resources, and verified destroy and orphan-check commands.
Also state which passwords, secrets, or certificates are not needed yet. No
cloud apply occurs merely because this milestone exists.

The [AWS reference VM runbook](aws-reference-vm.md) is the executable P1-04
handoff for these prerequisites, guarded lifecycle commands, and final cleanup.

## Milestone C — Complete Phase 1 deployment acceptance

Trigger: P1-04 through P1-06 implementation is ready and all workstation checks
pass.

Use a short-lived `single-node-reference` VM and run the entire Phase 1 path in
one planned session:

```text
AWS identity/cost/preflight
  -> AWS plan and confirmed apply
  -> generated ignored inventory
  -> Debian baseline twice and reboot validation
  -> standalone Incus bootstrap twice
  -> trusted provider setup
  -> provider plan and apply twice
  -> system-container DHCP/DNS/NAT/connectivity validation
  -> provider destroy and clean recreation
  -> final provider destroy
  -> AWS destroy and orphan check
```

Record command results, elapsed time, observed CPU, memory and disk use,
selected package and image versions, second-run drift, connectivity results,
cleanup state, and actual or estimated cost. Evidence must be redacted before
any part is published.

Milestone C fails if the VM or any billable networking or storage resource
remains after the final orphan check. A failed test is useful evidence, but it
is not a passed milestone.

## Later phase checkpoints

Every later phase must add a similar checkpoint before it is called complete.
At that time, enumerate new human prerequisites such as DNS delegation,
YubiKey enrollment, recovery-material handling, API tokens, certificates, or
test identities instead of requesting all future secrets during Phase 1.
