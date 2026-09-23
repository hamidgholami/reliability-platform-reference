# ADR-0005: Separate Incus bootstrap and resource ownership

- Status: accepted
- Date: 2026-08-28
- Decider: Hamid Gholami

## Context

Incus must be installed, initialized, and reachable before a declarative
provider can manage API resources. Ansible and the official Incus provider can
both call that API, so unclear ownership would cause drift or one tool to undo
the other. Network-zone transfer peers add a sensitive case: the provider
models all zone configuration, including the TSIG key, as one configuration map
that is recorded in OpenTofu state.

OpenTofu's `sensitive` marking redacts normal command output but does not remove
the value from state. BIND needs the same TSIG value on its side of the transfer
contract without deriving it from provider output.

## Decision

Use these non-overlapping ownership boundaries:

- Ansible owns Debian preparation, Incus package installation, daemon
  lifecycle, standalone initialization, cluster formation, server-global
  bootstrap settings, and guest operating-system or service configuration.
- The pinned official `lxc/incus` provider owns lifecycle-managed Incus
  projects, storage pools, networks, network zones, zone records, profiles, and
  instances after the API is healthy.
- Incus owns generated leases and DNS records derived from provider-managed
  resources.
- Ansible owns BIND configuration and protected key files, but not Incus zone
  or record objects.

When the private-DNS milestone begins, one secret source generates the TSIG key.
The provider and BIND automation consume that value directly at runtime; neither
reads it from the other's output. The provider owns all Incus transfer-peer
fields, including the key. Use Vault/OpenBao once it is available; any earlier
bootstrap value must be synthetic and disposable. This does not change resource
ownership.

Treat local OpenTofu state and saved plans as secret-bearing. Keep them in an
ignored operator-only directory, never publish them as evidence, and use no
committed variable file for the TSIG value. A later environment must adopt an
encrypted backend or supersede this design if protected local state is
insufficient for its threat model.

The provider connects only to a preconfigured, explicitly trusted Incus API.
Automatic client-certificate generation and automatic acceptance of a remote
server certificate are disabled.

## Consequences

- Host bootstrap can be rerun without competing with provider state.
- Network-zone objects and every field in their provider configuration have
  one state owner.
- The initial state contains a synthetic secret and requires the same handling
  discipline as credentials.
- Rotating TSIG requires coordinated provider and BIND changes and a tested
  overlap or maintenance procedure.
- Provider destroy removes its declared resources but does not uninstall,
  de-initialize, or remove Incus cluster members.

## Alternatives considered

- Manage all Incus API objects with Ansible: rejected because it would replace
  provider lifecycle, plan, drift, and teardown behavior with custom state
  handling.
- Let Ansible manage transfer-peer fields while the provider manages the zone:
  rejected because two tools would own one provider configuration map.
- Read the TSIG key back from OpenTofu state for BIND: rejected because it
  spreads state access and couples configuration management to secret-bearing
  provider output.
- Omit TSIG in the development environment: rejected because authenticated
  zone transfer is part of the Phase 1 DNS acceptance contract.

## Validation and reversal

Validate a second Ansible run and a second provider apply for idempotence and
no unexplained drift. Confirm that saved plans, state, logs, and evidence do not
expose the TSIG value. Exercise key rotation and provider-only destroy before
the Phase 2 private-DNS work item exits. Reverse or refine this boundary with a
superseding ADR if the provider schema or selected state backend changes
materially.

## References

- [Incus network zones](https://linuxcontainers.org/incus/docs/main/howto/network_zones/)
- [Official Incus provider](https://registry.terraform.io/providers/lxc/incus/1.1.1/docs)
- [OpenTofu sensitive data in state](https://opentofu.org/docs/language/state/sensitive-data/)
