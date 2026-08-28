# Reliability Platform Reference

An open, reproducible reference platform for demonstrating production-minded
DevOps and site reliability engineering practices across local, on-premises,
and cloud environments.

**Phase 0: architecture and governance** is complete. The repository contains
the accepted decisions, guardrails, and automated checks that constrain later
implementation. Phase 1 will add the reproducible Incus and network foundation
through its own reviewed implementation plan.

## Intended outcomes

- Show one coherent delivery and operations system, not disconnected tool demos.
- Reproduce the platform locally with Incus before consuming cloud resources.
- Demonstrate secure delivery, identity, secrets, observability, and recovery.
- Keep environment-specific differences behind documented profiles and inputs.
- Record trade-offs, failure modes, operational evidence, and recovery results.

## Scope

The planned platform connects Jenkins, Ansible, OpenTofu/Terraform-compatible
modules, Incus, Kubernetes, GitOps, Vault/OpenBao, Keycloak, artifact services,
observability, backup, and selected AWS and Azure integrations. Product choices
and placements are defined in [the architecture](docs/architecture.md) and the
[ADRs](docs/adr/).

This project does not promise a turnkey production platform, hide cloud cost,
copy employer code, or treat a successful deployment as proof of reliability.
See the [roadmap](docs/roadmap.md) for the staged implementation.

## Start here

Prerequisites for Phase 0 are Git, GNU Make, Node.js/npm, and Gitleaks.

```sh
make doctor
make check
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing a change. Architecture
or security boundary changes require an ADR.

## Current namespace plan

The registered public domain is `apadanalab.de`, with development services
below `dev.apadanalab.de`. Netcup currently provides both registration and
authoritative public DNS. Environment suffixes remain configurable inputs.

## License

Repository-authored material is licensed under Apache License 2.0. Third-party
products retain their own licenses; see [the license policy](docs/license-policy.md).
