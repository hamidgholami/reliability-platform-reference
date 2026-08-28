# Repository Instructions for Humans and Coding Agents

## Purpose

Build one reproducible reliability platform that demonstrates architecture,
delivery, identity, secrets, observability, recovery, and operations across a
local Incus environment and selected cloud profiles. Prefer an integrated
workflow with measured evidence over a catalogue of unrelated tools.

## Current phase

Phase 0 is complete. Phase 1 is next and requires a reviewed implementation plan
before deployable infrastructure is added. Do not add implementation or empty
future-product directories before the relevant phase begins.

## Non-goals and boundaries

- Do not copy or lightly rewrite employer, client, or private repository code.
- Do not publish private identifiers, URLs, hostnames, secrets, or screenshots.
- Do not imply production readiness, HA, compliance, or successful recovery
  without a test and evidence.
- Do not add a tool only to increase the product list. Explain its role in the
  end-to-end platform.
- Do not create Git submodules.

## Sources of truth

- `docs/architecture.md` defines the platform and bootstrap dependency graph.
- `docs/environment-profiles.md` defines supported deployment profiles.
- `docs/adr/` records architectural decisions.
- `docs/roadmap.md` defines phase ordering.
- `docs/plans/` contains task-level implementation plans.

When implementation and documentation disagree, resolve the disagreement in the
same change. Architecture and trust-boundary changes require an ADR.

## Required workflow

1. Read the relevant plan, ADRs, and nearby tests before editing.
2. Keep changes phase-scoped and small enough to review.
3. Use `make` targets as the public interface; do not make knowledge of an
   internal command a prerequisite for reviewers.
4. Run `make check` and report exact evidence. If a check cannot run, state why.
5. Document rollback and destructive behavior before enabling mutations.

The repository-wide validation targets are `make help`, `make doctor`,
`make lint-markdown`, `make lint-license`, `make scan-secrets`, and `make check`.

## Security and cost

- Use placeholders or secret-manager references, never real credentials.
- Do not generate or commit private keys, TOTP seeds, recovery shares, state,
  kubeconfigs, or bootstrap tokens.
- Default cloud paths to dry-run or plan. Require an explicit environment and
  confirmation before any create, apply, restore, failover, or destroy action.
- Put TTL, ownership, and cost labels on cloud resources when that phase begins.
- Treat local self-signed certificates as bootstrap-only. The target design uses
  an internal CA and ACME DNS-01 without publishing private addresses.

## Dependencies and licensing

Use exact dependency versions and keep automation actions pinned. Prefer
maintained open-source components and document the no-cost alternative when an
optional proprietary product appears. Preserve third-party notices and comply
with `docs/license-policy.md`.

## Authorship

AI tools may prepare working-tree changes but must not create, author, sign,
amend, or squash commits for Hamid. The human author reviews and creates every
commit with DCO sign-off and their own cryptographic signature.
