<!--
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
-->

# Phase 2 OpenBao foundation local acceptance

- Date: 2026-09-28
- Profile: `workstation-validation`
- Outer runtime: retained Lima VM on macOS
- Guest OS: Debian 13 arm64
- Incus: 6.0.4
- OpenBao: 2.6.3

This record summarizes redacted P2-02 service-foundation evidence. OpenTofu
state, inventories, CA state, private keys, package-verification cache, and
detailed machine evidence remain outside Git or in ignored local paths.

## Results

| Contract | Result |
| --- | --- |
| Substrate | Provider validation passed for the bounded `bao-01` container at `10.20.0.20`, including the host-enforced API ACL and private DNS alias. |
| Package provenance | Ansible required the pinned OpenBao primary-key fingerprint, verified the signed 2.6.3 checksum manifest, and matched the exact arm64 package checksum before installation. |
| Bootstrap TLS | The operator-managed root, current CRL, listener purpose, one-year validity, reviewed SANs, private-key match, and protected input modes passed validation. The Debian package did not generate its fallback self-signed key. |
| Service configuration | OpenBao uses the private TLS listener, integrated Raft storage, declarative file-audit configuration, and the package systemd unit with `MemorySwapMax=0`. No obsolete `mlock` setting or capability was added. |
| Runtime state | The service is active and enabled on OpenBao 2.6.3. After the guarded operator ceremony, its health response reports `initialized=true`, `sealed=false`, and `standby=false`. |
| Initialization and unseal | OpenBao encrypted its 1-of-1 Shamir share and initial root token to a dedicated passphrase-protected operator recovery key before returning them. The protected recovery directory remained outside Git, the share was streamed to the stdin-aware API path, and the final health check confirmed the unsealed state. |
| Plaintext rejection | A plaintext HTTP probe did not reach an OpenBao health endpoint; the accepted service path requires TLS and the supplied CA. |
| Protected files | Configuration, Raft, TLS, audit directory, and rotation configuration ownership and modes passed validation. Logrotate syntax also passed. |
| Idempotence | A complete second configuration run reported `changed=0`; the separate validation run also reported `changed=0`. |

## Limits

- This is local integration evidence, not promotion on the
  `single-node-reference` host.
- The single-operator 1-of-1 seal is intentionally not a production quorum.
  The initial root token remains encrypted and active pending creation and
  validation of scoped administrative access; no bootstrap administrator, KV
  mount, or online intermediate exists yet.
- Declarative audit configuration and rotation syntax are installed, but audit
  writes, rotation continuity, and fail-closed behavior require initialization
  and unseal and remain unaccepted.
- Browser access from the Mac remains deferred to the private VPN and split-DNS
  slice. No `/etc/hosts` entry or public route was added.

Operational commands and trust boundaries are documented in the
[OpenBao foundation runbook](../runbooks/openbao-foundation.md).
