<!--
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
-->

# Phase 1 deployment acceptance

Phase 1 passed its authoritative `single-node-reference` acceptance on
2026-09-23 in AWS Frankfurt. The run used a disposable `t4g.small` host with an
encrypted 30 GiB `gp3` root volume and Debian 13.7 ARM64. Account identifiers,
public addresses, cloud resource identifiers, SSH host keys, and client
certificate fingerprints are intentionally omitted.

## Results

| Boundary | Evidence |
| --- | --- |
| AWS bootstrap | The reviewed plan contained 11 creates and no changes or destroys. The instance passed both AWS status checks. |
| Debian baseline | The first apply completed in 9m07s with 53 changes and no failures. Validation passed, including SSH syntax, fresh authenticated reconnection, AppArmor, synchronized time, forwarding, namespaces, and the listener allowlist. |
| Baseline idempotence | The complete second apply finished in 7m56s with zero changes and zero failures. |
| Incus host | Debian `incus-base` `6.0.4-2+deb13u10` installed Incus 6.0.4. The first bootstrap completed in 1m09s and the second in 47s with zero changes. Standalone API health, HTTPS reachability, and non-root operator access passed. |
| Client trust | Separate human and OpenTofu TLS identities matched the pinned server certificate and authenticated successfully. |
| Provider apply | OpenTofu created exactly five resources: one restricted project, one `dir` pool, one managed bridge, one unprivileged system-container profile, and one smoke container. |
| Runtime behavior | The Debian 13.7 ARM64 container received an address from the configured DHCP range. Its managed name and an external name resolved, and outbound IPv4 connectivity passed. IPv6 remained disabled by policy. |
| Provider idempotence | The second plan reported no changes and the second apply reported `0 added, 0 changed, 0 destroyed`. |
| Rebuild | Provider destroy removed all five resources without removing Incus or trust. A clean plan recreated all five resources and runtime validation passed again. |
| Final cleanup | The final provider destroy left zero resources in provider state. Both disposable trust entries were revoked. OpenTofu then destroyed all 11 AWS resources and left empty bootstrap state. Direct EC2 checks found no live tagged resources. |

The smoke container resolved from `images:debian/13` to image fingerprint
`38bffadf33a93e9965d9876ae03b7fae5aacdeda3141805e7ed9e864949cbc13`.
Recording the resolved fingerprint makes this run identifiable even though the
input alias can advance.

## Runtime and cost observations

The reference host had 2 vCPUs and about 1.82 GiB usable memory. During a
15-second sample around the final runtime validation, peak observed host usage
was 3% CPU busy and about 199 MiB memory. The running smoke container reported
12 processes and about 22 MiB current memory. The host used about 1.75 GiB of
its root filesystem after provisioning and image download.

The AWS instance lifetime was approximately 47 minutes. Using the rates
reviewed immediately before apply—USD 0.0192/hour for `t4g.small`, USD
0.005/hour for public IPv4, and USD 0.0952/GiB-month for `gp3`—the estimated
in-scope infrastructure cost was about USD 0.022 before tax and data transfer.
This is an estimate, not an AWS invoice.

The Resource Groups Tagging API continued to list five recently deleted
resources immediately after teardown. The orphan check treated those known
entries as deletion tombstones only after resource-specific EC2 APIs confirmed
that no live instance, volume, network, or access resource remained.

## Limitations

- The resource sample covers the final validation window, not full-run
  telemetry; no monitoring agent was installed for this short-lived milestone.
- One small standalone host, local `dir` storage, and one system container do
  not establish high availability, production capacity, or disaster recovery.
- The test proves managed-bridge DHCP, DNS, NAT, and outbound connectivity. It
  does not cover the deferred private authoritative DNS and PKI design.
- Lima remains optional developer feedback and is not part of this deployment
  acceptance claim.
