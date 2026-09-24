<!--
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
-->

# Private DNS

P2-01 uses Incus network zones as a hidden primary and two BIND 9 containers as
query-serving authoritative secondaries. The service is private to `platform0`:
Incus transfers on `10.20.0.1:1053`, while BIND listens on `10.20.0.10:53` and
`10.20.0.11:53`. Neither service is exposed on a public interface.

Incus owns generated instance, gateway, and reverse records. OpenTofu owns the
forward and reverse zones, transfer peers, service containers, and manual
`resolver` record. Ansible owns the BIND packages and guest configuration.
Transferred zone files must never be edited by hand.

## Bootstrap inputs

Use the retained local Lima VM for normal development. Complete the host,
Incus-client, and provider prerequisites in the existing runbooks first. Then
generate one ignored, mode-`0600` TSIG input file:

```sh
export PROFILE=workstation-validation
export INCUS_CONFIG_DIR="$PWD/.cache/incus/opentofu"
export INCUS_REMOTE=rpr-target

CONFIRM=generate-private-dns-tsig-workstation-validation \
  make private-dns-secrets
```

The command refuses to overwrite an existing file. The generated values are
synthetic environment secrets: do not print, commit, or copy them into evidence.
Back up the file together with the secret-bearing OpenTofu state when the
environment must be recoverable. Losing either requires a reviewed TSIG
rotation or a clean environment recreation.

Enable and validate the private Incus transfer listener on the selected host:

```sh
make private-dns-primary-check
CONFIRM=private-dns-primary-workstation-validation-incus-lima-01 \
  make private-dns-primary
make validate-private-dns-primary
```

Use the actual `TARGET_HOST` in the confirmation string. This server-global
setting remains Ansible-owned; provider destroy does not remove it.

## Provision and configure

The ordinary provider workflow creates the zones, record, profile, and two
service containers and generates ignored Ansible inventory:

```sh
make plan
CONFIRM=apply-incus-workstation-validation-rpr-target make apply
make validate

CONFIRM=configure-private-dns-workstation-validation-rpr-target \
  make configure-private-dns
make validate-private-dns
```

Run `make plan` again after configuration. A converged provider plan contains no
resource changes. Run `make configure-private-dns` a second time to require
`changed=0` on both containers.

Debian 13 currently supplies Incus 6.0 LTS. That line predates Incus DNS NOTIFY
support, so BIND polls the hidden primary instead. Incus advertises a 120-second
SOA refresh, and the role sets BIND's per-zone minimum and maximum refresh to
the same value; BIND's default minimum would otherwise delay refresh for at
least 300 seconds. A future supported LTS can adopt NOTIFY after a separate
compatibility review. Do not move this reference environment to a short-lived
monthly Incus release solely for faster DNS propagation.

## Runtime acceptance

The guarded acceptance probe checks generated A/PTR answers, the provider-owned
manual record, bounded periodic refresh, removal of its temporary record, and
queries through either secondary while the other is stopped:

```sh
CONFIRM=accept-private-dns-workstation-validation-rpr-target \
  make accept-private-dns
```

The probe reserves `acceptance-refresh-probe.dev.apadanalab.de` at
`10.20.0.220` only for its duration. A trap deletes the record, refreshes stale
secondary data after failure, and restarts any stopped service container. It
writes non-secret evidence to ignored `.cache/private-dns/acceptance.json`.

The two containers are separate DNS processes on one Incus host. Surviving one
container stop does not establish host-level high availability.

## Teardown and recreation

Use the provider destroy workflow only for disposable acceptance environments:

```sh
CONFIRM=destroy-incus-workstation-validation-rpr-target make destroy
```

Destroy removes provider-owned zones, records, profiles, and instances but does
not uninstall Incus, revoke client certificates, remove the server-global DNS
listener, or delete the protected TSIG file. Recreate with `make plan`, `make
apply`, and the configuration sequence above. Delete or rotate the ignored TSIG
file separately only when the environment lifecycle requires it.
