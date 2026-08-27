# Phase 0 Plan: Architecture and Governance

- Status: in progress
- Owner: Hamid Gholami
- Started: 2026-08-27
- Milestone: create `Phase 0 - Architecture and governance` after publication

## Outcome

Create a trustworthy, reviewable repository boundary before deployable
infrastructure begins. Phase 0 decides what the platform is, what it is not, how
trust is bootstrapped, and what evidence later work must produce.

## Guardrails

- All Git commits are reviewed, authored, DCO-signed, and cryptographically
  signed by Hamid or the actual human contributor. AI tools do not commit.
- No employer code, private identifiers, secrets, state, or recovery material.
- No cloud resources or external mutations are created in Phase 0.
- No empty implementation directories are added for future products.
- Domain registration is not assumed successful until independently validated.

## Work items

The IDs below become GitHub issues when the local repository is published.

### P0-01 — Repository and legal baseline

- [x] Initialize `main` locally without creating a commit.
- [x] Add Apache-2.0 `LICENSE`, `NOTICE`, and `AUTHORS.md`.
- [x] Add contribution, DCO, security, authorship, and dependency rules.
- [x] Add ignore and editor policies.
- [ ] Human reviews and creates the signed initial commit.

Acceptance: license checks pass and the working tree contains no real secret.

### P0-02 — Platform boundary and profiles

- [x] State purpose, non-goals, layers, and explicit non-claims.
- [x] Define local/on-prem and AWS environment profiles.
- [x] Record the integrated-platform boundary in ADR-0001.
- [x] Record control-service placement in ADR-0002.
- [ ] Review and accept the draft architecture as the implementation baseline.

Acceptance: every planned product maps to a platform capability and environment.

### P0-03 — Foundation and trust design

- [x] Draft the bootstrap dependency graph and ownership boundaries.
- [x] Draft local address, DHCP, DNS, and cloud-mapping rules.
- [x] Draft external DNS and internal/public PKI paths.
- [x] Define the operator trust kit contract.
- [ ] Confirm domain registration and authoritative delegation.
- [ ] Validate address ranges against the actual host and VPN networks.

Acceptance: a reviewer can identify every bootstrap dependency and the recovery
route when Kubernetes is unavailable.

### P0-04 — Reliability, security, and cost contracts

- [x] Define initial SLO/RPO/RTO classes without claiming achievement.
- [x] Document assets, trust boundaries, priority threats, and initial controls.
- [x] Define local-first cloud cost and teardown policy.
- [x] Define naming and clean-room migration policies.
- [ ] Add a data-flow diagram when implementation interfaces are known.

Acceptance: later plans can attach tests to an objective, threat, and rollback.

### P0-05 — Repository quality gates

- [x] Add one public `make` interface for local checks.
- [x] Add Markdown, license, and Gitleaks checks.
- [x] Add a least-privilege GitHub Actions workflow with pinned dependencies.
- [x] Document target branch-protection settings.
- [ ] Create the remote repository and enable private vulnerability reporting.
- [ ] Apply and capture branch-protection settings after the first human commit.

Acceptance: local `make check` succeeds and the three CI jobs succeed remotely.

## Deferred work outside Phase 0

Reviewing, scanning, migrating, or archiving the legacy repositories is
explicitly deferred until this repository reaches its stable-release outcome.
It is not a Phase 0 exit criterion and must not distract from implementing the
new platform. The clean-room migration policy remains documented for that later
review.

## Verification

Run from the repository root:

```sh
make doctor
make check
git status --short
```

Review the architecture, ADRs, threat model, and environment assumptions
manually. After publishing, confirm the `Markdown`, `Secrets`, and `License` jobs
and capture branch-protection evidence.

## Rollback

Phase 0 creates only local files and Git metadata. Before the human's first
commit, individual changes can be edited or omitted. After publication, reverse
an accepted architecture decision with a superseding ADR; do not rewrite shared
history. Domain and GitHub configuration require their own provider recovery
procedures.

## Exit criteria

Phase 0 is complete only when:

- scope, non-goals, profiles, service placement, bootstrap order, DNS/PKI,
  network, and trust boundaries have human approval;
- license, authorship, DCO, security, contribution, and dependency rules agree;
- local checks and required remote checks pass;
- branch protection and private vulnerability reporting are enabled;
- domain and address assumptions are validated or explicitly deferred;
- no substantial Phase 1 infrastructure implementation has started early.
