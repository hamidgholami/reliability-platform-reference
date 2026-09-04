# ADR-0004: Prefer native Incus capabilities in local profiles

- Status: accepted
- Date: 2026-08-28
- Decider: Hamid Gholami

## Context

The reference platform can easily accumulate overlapping infrastructure tools.
Each additional service adds installation, configuration, security, monitoring,
backup, upgrade, and recovery work. It can also hide useful capabilities already
provided by Incus, the primary local and on-premises substrate.

Avoiding all external tools is not the objective. The platform still needs a
clear way to close capability gaps that materially affect its acceptance
criteria.

## Decision

For `workstation-validation`, `single-node-reference`, and on-premises profiles,
investigate the native Incus capability before proposing another infrastructure
service. Evaluate it against the actual requirement, including automation,
security, availability, observability, backup, recovery, and operational cost.

Use the Incus capability when it is sufficiently fit for the profile, even if a
specialized product offers more features. Add an external tool only when the
remaining gap is documented and the new tool has a narrow owner, validation
path, and removal or replacement strategy.

Cloud profiles may use provider-native equivalents when they satisfy the same
platform contract. They do not need to reproduce Incus implementation details.

## Consequences

- Capability discovery becomes a required planning step before dependency
  selection.
- The platform demonstrates deeper Incus knowledge and carries fewer services.
- A rejected native capability must have a concise gap analysis rather than a
  preference-only justification.
- Incus-specific implementations may need adapters for cloud profiles, but the
  common acceptance contract remains portable.

The DNS design demonstrates the rule: Incus network zones generate and own the
private records; BIND is added only because the Incus zone server exposes AXFR
and does not answer ordinary client queries.

## Validation and reversal

Every Phase 1 infrastructure dependency must link to an Incus capability review
or explain why no equivalent exists. Revisit this decision if the review cost or
Incus coupling repeatedly exceeds the operational savings.

## References

- [Incus documentation](https://linuxcontainers.org/incus/docs/main/)
- [Incus networking](https://linuxcontainers.org/incus/docs/main/networks/)
- [Incus network zones](https://linuxcontainers.org/incus/docs/main/howto/network_zones/)
