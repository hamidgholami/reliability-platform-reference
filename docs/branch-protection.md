# Branch Protection Policy

Apply these settings to `main` after the GitHub repository is created:

- require a pull request before merge;
- require at least one approving review when another maintainer is available;
- dismiss stale approvals after new changes;
- require conversation resolution;
- require linear history;
- block force pushes and deletion;
- require signed commits;
- require the `Markdown`, `Secrets`, and `License` checks from `quality.yml`;
- do not allow administrators to bypass controls for routine work.

The project also requires a DCO `Signed-off-by` trailer on every commit. Add an
appropriate DCO check before accepting outside contributions.

These are remote-host settings and cannot be enforced by the local skeleton.
Record a screenshot or API output as Phase 0 evidence after configuration.
