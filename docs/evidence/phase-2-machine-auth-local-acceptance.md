<!--
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
-->

# Phase 2 machine-authentication local acceptance

- Date: 2026-09-29
- Profile: `workstation-validation`
- Runtime: Debian 13 guests on the retained Lima and Incus host
- Service: OpenBao 2.6.3

The guarded `make configure-machine-auth` target completed against `bao-01`
and `smoke-01`. The result below contains no credential, certificate, token,
or recovery material.

| Contract | Observed result |
| --- | --- |
| Client identity | Ed25519 X.509 key generated inside `smoke-01`; public certificate exact-pinned to `rpr-p203-machine`. |
| Private DNS | `smoke-01` resolved the OpenBao alias through the private BIND secondaries before recovery. |
| Root recovery | The target confirmed temporary root revocation before machine acceptance. |
| Machine login | Certificate login returned the dedicated `rpr-p203-machine` policy with a five-minute maximum token lifetime. |
| Policy | The client had `read` on `database/creds/rpr-p203-read` and `update` on `ssh-client-signer/sign/rpr-p203-probe`; operator KV and system mounts were denied. |
| Cleanup | The acceptance login token was revoked. |

This proves the machine-authentication boundary locally. The database and SSH
credential paths are policy placeholders until their respective P2-03 slices
configure those engines. The reference host has not been promoted.
