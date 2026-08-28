# Cost and Resource Policy

Local validation is the default. Cloud resources are exceptional, explicit, and
temporary unless a later ADR establishes a justified standing service.

## Required safeguards

- Every cloud profile declares an owner, purpose, estimated maximum cost, and
  destruction deadline before creation.
- Automation defaults to validation or plan and requires an explicit environment
  selection before apply or destroy.
- Resources receive ownership, environment, repository, and expiry labels/tags.
- Budget alerts are configured before the first billable experiment.
- Expensive managed services, large instance types, public IPv4 addresses, and
  durable storage require written justification.
- Teardown is tested as part of creation; orphan discovery is part of CI or the
  scheduled operations workflow.

## Phase 0 budget

Phase 0 creates no cloud infrastructure. Its external cost is the registered
`apadanalab.de` domain. Netcup authoritative DNS and local Incus form the
no-additional-subscription path; a second public DNS provider is not required.

Prices and free-tier terms are volatile. Each cloud execution plan must record a
fresh estimate rather than relying on values copied into this repository.
