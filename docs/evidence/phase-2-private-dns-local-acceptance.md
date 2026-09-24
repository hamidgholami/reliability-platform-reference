<!--
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
-->

# Phase 2 private-DNS local acceptance

- Date: 2026-09-24
- Profile: `workstation-validation`
- Outer runtime: retained Lima VM on macOS
- Guest OS: Debian 13 arm64
- Incus: 6.0.4
- BIND: `1:9.20.29-1~deb13u1` on both secondaries

This record summarizes redacted P2-01 evidence. Runtime inventories, OpenTofu
state, TSIG values, and detailed machine evidence remain in ignored local
paths. No secret value is reproduced here.

## Results

| Contract | Result |
| --- | --- |
| Hidden primary | Incus listened on private `10.20.0.1:1053`; the listener remained healthy across provider teardown and recreation. |
| Provider boundary | OpenTofu created exactly 11 resources: one project, pool, bridge, two zones, one manual record, two profiles, and three containers. |
| Service placement | `dns-01` and `dns-02` ran at stable private addresses `.10` and `.11` in unprivileged, non-nested containers. |
| Transfer authentication | Both BIND servers retrieved forward and reverse zones from Incus through their distinct per-zone TSIG inputs. |
| Authoritative behavior | Both servers answered the generated `smoke-01` A/PTR records and the provider-owned `resolver` A record, refused recursion, and refused unauthenticated AXFR. |
| Refresh | A temporary acceptance record reached both secondaries through the bounded Incus 6.0 LTS polling path. BIND clamps both zone refresh bounds to the Incus 120-second SOA value. |
| Secondary continuity | Either BIND server continued answering generated and manual records while the other container was stopped. |
| Cleanup | The temporary record was removed, both secondaries refreshed, and the only remaining manual forward-zone record was provider-owned `resolver`. |
| Public DNS | Public queries returned no A record for the private zone apex, resolver, smoke instance, or either DNS secondary. |
| Idempotence | A second OpenTofu apply reported `0 added, 0 changed, 0 destroyed`; a second Ansible run reported `changed=0` on both containers. |
| Recreation | Provider destroy removed exactly 11 resources and left managed state empty. Clean plan/apply recreated all 11 resources; substrate, DNS, runtime acceptance, and both convergence checks passed again. |
| Repository checks | `make check` passed, including formatting, lint, mocked provider tests, confirmation/trust safety tests, and secret scanning. |

## Limits

- This is local integration evidence, not promotion on the
  `single-node-reference` host.
- Two containers on one Incus host are independent DNS processes, not
  host-level high availability.
- Incus 6.0 LTS predates network-zone DNS NOTIFY. Immediate change propagation
  is therefore not claimed; bounded 120-second polling is the accepted local
  contract.
- Workstation split DNS and private routing are intentionally deferred. The
  test queries from the platform network through Incus execution.
- The TSIG file and OpenTofu state are secret-bearing local recovery inputs and
  are not acceptance artifacts.

Operational commands and recovery boundaries are documented in the
[private-DNS runbook](../runbooks/private-dns.md).
