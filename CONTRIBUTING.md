# Contributing

Thank you for improving Reliability Platform Reference. Contributions should
strengthen the coherent platform or its operational evidence rather than add an
isolated product demonstration.

## Before changing the repository

1. Read [AGENTS.md](AGENTS.md), the [architecture](docs/architecture.md), and
   relevant ADRs.
2. Open or reference an issue with the problem, acceptance criteria, and phase.
3. Add an ADR when changing a platform boundary, trust boundary, service
   placement, foundational dependency, or public interface.
4. Never copy employer or client code, identifiers, credentials, or internal
   documentation. Reimplement concepts from first principles.

## Development workflow

Create a focused branch, make a small reviewable change, and run:

```sh
make doctor
make check
```

Document validation evidence and any test that was intentionally not run in the
pull request. Do not claim high availability, recovery, or security properties
without executable evidence.

## Commits and sign-off

The project uses the Developer Certificate of Origin rather than a contributor
license agreement. Every commit must be authored and signed off by its human
author:

```sh
git commit -s -S
```

The `Signed-off-by` trailer certifies the contribution under the DCO. The `-S`
flag cryptographically signs the commit when the author's Git signing setup is
available. Automation and AI assistants must not author or sign commits for a
human contributor.

## Dependency policy

- Prefer maintained, inspectable, no-cost open-source dependencies.
- Pin CI actions and automation dependencies to an immutable commit or exact
  release, with the readable version beside it.
- Record license, purpose, alternative, and operational consequence for every
  foundational dependency.
- Do not use Git submodules. Pin exact external inputs through the package or
  automation mechanism that consumes them.

## Pull-request expectations

A change is complete when its documentation, tests, security implications,
rollback path, and relevant ADRs agree. Required checks are defined in
[the branch-protection policy](docs/branch-protection.md).
