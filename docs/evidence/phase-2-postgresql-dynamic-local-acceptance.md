# P2-03 dynamic PostgreSQL local acceptance

On 2026-09-29, the `workstation-validation` profile completed the protected
PostgreSQL signing and database-engine configuration. The recovery ceremony
revoked its temporary root and recovery tokens before the private TLS
listener was activated. The generated server key remained in `pg-01`; the
OpenBao database administrator was a non-superuser `CREATEROLE` account.

The `smoke-01` machine identity requested a `rpr-p203-read` credential from
OpenBao and read the one synthetic probe row over verified TLS. A new
connection with that credential was rejected after revoking its machine
token. A separate 30-second lease was rejected after expiry. The acceptance
play ended with 17 successful tasks, no failed or unreachable hosts, and one
package-install change.

PostgreSQL reported `listen_addresses=10.20.0.21` and `ssl=on`. The read
group had `SELECT` on the probe table and lacked `INSERT`, `UPDATE`, and
`DELETE`. Protected bootstrap password and certificate transfer files were
absent from both guests after the ceremony.

This is retained-Lima evidence. Clean local recreation and promotion to the
`single-node-reference` environment remain part of Phase 2 acceptance.
