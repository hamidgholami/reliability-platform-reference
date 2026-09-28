# Infrastructure roots

Each directory below this one is an independent OpenTofu root with independent
state and lifecycle ownership.

- `bootstrap/aws-single-node` creates the disposable Debian 13 host and its
  minimal AWS network boundary through the guarded P1-04 Make targets.
- `incus` manages resources through the Incus API after Ansible has made that
  API healthy. It uses a pre-enrolled, isolated provider identity and owns the
  restricted project, local `dir` pool, managed bridge, profiles, containers,
  private network zones and records, and host-enforced ACLs required by the
  active delivery slice. Its create/update plan path rejects destructive
  actions.

Initialization downloads pinned providers but does not contact an
infrastructure API. Validation then runs offline. Planning the AWS root reads
AWS identity, billing, pricing, AMI, and availability data and therefore
requires the explicit live inputs documented in the
[AWS runbook](../docs/runbooks/aws-reference-vm.md). Apply and destroy require
separate exact confirmations.

The Incus root is target-neutral. `single-node-reference` is the authoritative
acceptance profile; `workstation-validation` can exercise the same root through
Lima without changing its resource contract.

Never share a state path between these roots. State, saved plans, credentials,
and generated client certificates are local operator material and must not be
committed.
