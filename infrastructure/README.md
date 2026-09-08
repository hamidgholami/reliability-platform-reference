# Infrastructure roots

Each directory below this one is an independent OpenTofu root with independent
state and lifecycle ownership.

- `bootstrap/aws-single-node` may eventually create the disposable Debian 13
  host and its minimal AWS network boundary.
- `incus` will manage resources through the Incus API after Ansible has made
  that API healthy. P1-01 contains only its provider constraint; substrate
  resources start in P1-05.

Initialization downloads pinned providers but does not contact an
infrastructure API. Validation then runs offline. Planning the AWS root reads
AWS data sources and therefore requires credentials; applying or destroying it
is not enabled in P1-01.

Never share a state path between these roots. State, saved plans, credentials,
and generated client certificates are local operator material and must not be
committed.
