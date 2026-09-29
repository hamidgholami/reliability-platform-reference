# P2-03 PostgreSQL local preparation

On 2026-09-29, the workstation-validation profile created `pg-01` at
`10.20.0.21` in the restricted `rpr-dev` Incus project. The provider apply
reported three additions, two in-place updates, and no deletions. Subsequent
`make validate` passed, including the private DNS answer from both secondaries.

The Ansible guest configuration installed Debian 13's
`postgresql-17` package at `17.11-0+deb13u1`, started the cluster, and
created the `rpr_p203` database with one `public.probe` synthetic row. It
verified `listen_addresses=127.0.0.1` and `ssl=off`. No remote database login
exists yet. The play ended with 17 successful tasks, zero failures, and zero
unreachable hosts. Most elapsed time was the initial Debian package download.
The immediate rerun completed in about five seconds with zero changes.

This is local preparation evidence. The signed listener certificate,
restricted `pg_hba.conf`, dynamic OpenBao credential lifecycle, and clean
recreation later passed; see the
[P2-03 record](phase-2-p203-clean-recreation-local-acceptance.md).
