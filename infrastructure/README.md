# Infrastructure roots

Each directory below this one is an independent OpenTofu root with independent
state and lifecycle ownership.

- `bootstrap/aws-single-node` creates the disposable Debian 13 host and its
  minimal AWS network boundary through the guarded P1-04 Make targets.
- `incus` manages resources through the Incus API after Ansible has made that
  API healthy. Its first P1-05 slice verifies a pre-enrolled, isolated provider
  identity through a read-only data source; substrate resources follow only
  after this trust boundary passes.

Initialization downloads pinned providers but does not contact an
infrastructure API. Validation then runs offline. Planning the AWS root reads
AWS identity, billing, pricing, AMI, and availability data and therefore
requires the explicit live inputs documented in the
[AWS runbook](../docs/runbooks/aws-reference-vm.md). Apply and destroy require
separate exact confirmations.

Never share a state path between these roots. State, saved plans, credentials,
and generated client certificates are local operator material and must not be
committed.
