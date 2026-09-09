# Phase 1 operator interface

P1-01 establishes static validation and discoverable command boundaries. It
does not authorize creation of a Lima VM, an EC2 instance, or an Incus resource.

## Workstation-only commands

Run `make setup` once to install the pinned Python and Ansible dependencies into
`.venv` and the pinned collection into `.cache`. These paths are ignored. Then
run:

```sh
make doctor
make check
make lima-validate
```

`make setup` may contact Python, Ansible Galaxy, and OpenTofu registries, but it
contacts no infrastructure API. `make check` formats nothing, requires no
infrastructure credentials, and creates no resources. Its pinned Markdown tool
may be obtained through `npx` when it is not already cached. `make
lima-validate` checks only the YAML and does not start a VM.

The OpenTofu test replaces the AWS provider with a mock. It checks the minimum
instance, storage, metadata, and ingress contract and proves that `/0` operator
CIDRs are rejected without sending any AWS request.

Do not activate `.venv` manually for repository commands: Make invokes its
binaries explicitly, which avoids accidentally using a global Ansible install.
The Phase 1 path uses standard Ansible SSH. Mitogen is deliberately deferred
until a later multi-node benchmark proves that connection overhead is material.

## Optional disposable Lima VM

Lima is a feedback accelerator, not a deployment prerequisite. The wrapper
requires the exact reviewed profile and confirmation before creation or
deletion:

```sh
PROFILE=workstation-validation CONFIRM=create-rpr-p1 make lima-up
make lima-stop
PROFILE=workstation-validation CONFIRM=delete-rpr-p1 make lima-delete
```

The VM uses two CPUs, 4 GiB memory, a 30 GiB disk, and no host mounts or bundled
containerd. Creating it downloads a pinned Debian 13 arm64 cloud image and
consumes local resources. Delete it with `make lima-delete`; there is no
repository-owned data recovery after deletion.

## Reference target and AWS boundary

The sanitized inventory uses the documentation-only address `192.0.2.10` and
cannot identify a real host. Later work generates operator-local inventory from
the selected target.

The AWS root is independently stateful and defines the accepted minimal VM
contract. P1-04 enables its guarded plan, apply, destroy, and orphan-check
commands. The wrapper generates ignored runtime variables and inventory; do not
copy example values into a committed file. Follow the
[AWS reference VM runbook](aws-reference-vm.md) for account preparation, cost
checks, exact confirmations, target promotion, and cleanup.

P1-02 enables `make preflight`, `make baseline-check`, `make baseline`, and
`make validate-baseline` for one explicit target. Follow the
[Debian baseline runbook](debian-baseline.md); the mutating baseline requires an
exact confirmation string, while target inventory and key material stay
outside Git. P1-03 likewise enables `make preflight-incus`,
`make bootstrap-incus`, and `make validate-incus`; follow the
[standalone Incus host runbook](incus-host.md).

The [end-to-end milestone runbook](end-to-end-milestones.md) defines when local
checks are insufficient and a disposable real environment must be exercised.
Incus-provider commands remain disabled until their named Phase 1 work item
implements the corresponding safety and acceptance checks. `make help` is the
authoritative list and labels unavailable commands.
