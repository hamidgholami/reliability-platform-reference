# Cost and Resource Policy

Workstation validation is the default. Cloud resources are explicit and
temporary unless an ADR establishes a justified standing service. Phase 1 may
create one minimal EC2 reference host under ADR-0006; it must be destroyed after
the implementation session and is not a standing environment.

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

## Phase 1 AWS ceiling

The initial plan contains one `t4g.small`, one 30 GiB encrypted `gp3` root
volume, and one temporary public IPv4 in `eu-central-1`. It excludes NAT
gateways, Elastic IPs, load balancers, and paid Marketplace images. A live cost
and free-tier check, notification-only AWS budget, expiry tag, explicit apply
confirmation, destroy, and orphan check are mandatory. An existing suitable
account budget may satisfy the budget requirement.
