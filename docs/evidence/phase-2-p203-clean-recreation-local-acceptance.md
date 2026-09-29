# P2-03 clean local recreation acceptance

On 2026-09-29, `workstation-validation` was rebuilt from an empty Incus
provider state and a new Debian 13 Lima VM. The retained offline root CA was
used to sign a new OpenBao intermediate; the previous instance's recorded CSR
was archived rather than reused. The new OpenBao recovery kit was backed up,
and the initial root token was retired after authenticated recovery passed.

| Boundary | Clean-environment result |
| --- | --- |
| Host and provider | Debian baseline and Incus bootstrap passed; the host retained only an Ed25519 SSH host key. A reviewed plan created 21 resources with no deletes. Final substrate validation passed and a later plan showed no drift. |
| Private DNS | Both BIND secondaries served forward and reverse zones. Runtime acceptance proved record propagation, cleanup, and service through either secondary while the other was stopped. |
| OpenBao | Release, TLS listener, audit behavior, KV policy, new intermediate CA, listener issuance and renewal, root-token retirement, and exact-pinned machine authentication passed. The service remained initialized, active, and unsealed. |
| PostgreSQL | Debian `postgresql-17` version `17.11-0+deb13u1` was installed. The machine client read the synthetic row over verified TLS; revoked and expired dynamic credentials were rejected. The acceptance play had 17 successful tasks and no failures. |
| SSH certificates | The target retained only an Ed25519 host key and accepted only Ed25519 user certificates. Allowed login passed; wrong principal, excessive lifetime, forwarding extension, and expired certificate were rejected. The temporary client key and certificate were removed. The acceptance play had 23 successful tasks and no failures. |

At the final resource snapshot, the 4-GiB Lima host used 826 MiB of memory
and 5.9 GiB of its 30-GiB root filesystem. Incus reported 447 MiB for
`bao-01`, 36 and 35 MiB for the DNS containers, 276 MiB for `pg-01`, 304 MiB
for `smoke-01`, and 142 MiB for `ssh-test-01`. These are point-in-time
figures with shared accounting, not measured peaks or proof of a 2-GiB AWS
host fit.

This completes P2-03 clean local acceptance. Promotion to
`single-node-reference` remains open. The disposable SSH target remains in
the local provider state until its removal is reviewed separately.
