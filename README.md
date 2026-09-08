# Reliability Platform Reference

An open, reproducible reference platform for demonstrating production-minded
DevOps and site reliability engineering practices across local, on-premises,
and cloud environments.

**Phase 0: architecture and governance** is complete. Phase 1 now delivers one
minimal standalone Incus foundation on a Debian 13 VM, initially supplied by a
small isolated AWS OpenTofu root. P1-01 provides pinned repository interfaces
and fast quality gates; the Mac workstation is used for checks and optional
disposable integration rather than persistent platform hosting.

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

The active Phase 1 checks require Git, GNU Make, Node.js/npm, Gitleaks,
Python 3, and OpenTofu 1.12.6. Install the pinned local dependencies first:

```sh
make setup
make doctor
make check
```

See the [Phase 1 operator interface](docs/runbooks/phase-1-operator-interface.md)
before any optional VM work. No AWS lifecycle command is enabled yet.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing a change. Architecture
or security boundary changes require an ADR.

## Current namespace plan

The registered public domain is `apadanalab.de`, with development services
below `dev.apadanalab.de`. Netcup currently provides both registration and
authoritative public DNS. Environment suffixes remain configurable inputs.

## License

Repository-authored material is licensed under Apache License 2.0. Third-party
products retain their own licenses; see [the license policy](docs/license-policy.md).
