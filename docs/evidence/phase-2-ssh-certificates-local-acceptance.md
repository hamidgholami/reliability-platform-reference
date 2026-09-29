# P2-03 SSH certificates local acceptance

On 2026-09-29, the `workstation-validation` profile configured one OpenBao
Ed25519 SSH client CA and a signing role fixed to the `rpr-probe` principal.
The protected recovery ceremony completed without errors. The disposable
`ssh-test-01` target installed the CA public key, retained only an Ed25519
host key, and started a certificate-only daemon for the non-sudo account.

From `smoke-01`, the exact-pinned machine identity obtained a 30-second
Ed25519 user certificate and logged in as `rpr-probe`. OpenBao rejected
requests for the `root` principal, a ten-minute lifetime, and a forwarding
extension. SSH rejected the certificate after expiry. The acceptance play
ended with 23 successful tasks and no failed or unreachable hosts. It revoked
the machine token and removed the temporary client key and certificate;
an independent check found the temporary directory absent.

The effective target daemon policy showed `DisableForwarding yes`,
`HostKeyAlgorithms ssh-ed25519`,
`PubkeyAcceptedAlgorithms ssh-ed25519-cert-v01@openssh.com`,
`CASignatureAlgorithms ssh-ed25519`, `AuthorizedKeysFile none`, and password
authentication disabled. The daemon was active after the target playbook
rerun. That rerun also restored `/run/sshd` after stopping the service, so
configuration validation and restart complete on repeated application.

This is retained-Lima integration evidence. The
[clean local recreation](phase-2-p203-clean-recreation-local-acceptance.md)
also passed; promotion to `single-node-reference` remains open. The
disposable target remains in the local provider state pending a separately
reviewed removal.

At this local snapshot, the 4-GiB Lima host reported 791 MiB used memory,
3,130 MiB available memory, and 6.0 GiB of its 30-GiB root filesystem used
with six running containers. Per-service peaks and a 2-GiB cloud-host fit
decision remain to be measured before AWS promotion.
