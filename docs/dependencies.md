# Pinned dependencies

P1-01 uses exact versions so local checks and CI exercise the same interfaces.
Provider checks download binaries into ignored working directories; no
third-party source or binary is redistributed by this repository.

| Component | Version | Purpose | Upstream license | No-cost alternative or consequence |
| --- | --- | --- | --- | --- |
| [Ansible Core](https://github.com/ansible/ansible) | 2.21.3 | Target configuration engine | GPL-3.0-or-later | Foundational choice; replace playbooks to migrate |
| [ansible-lint](https://github.com/ansible/ansible-lint) | 26.8.0 | Static Ansible checks | GPL-3.0-or-later | Manual review loses repeatable policy checks |
| [certifi](https://github.com/certifi/python-certifi) | 2026.7.22 | Pinned CA bundle for Python and Galaxy TLS validation | MPL-2.0 | Use a correctly configured operating-system CA bundle |
| [Molecule](https://github.com/ansible/molecule) | 26.8.0 | Role integration-test harness for later work items | MIT | Direct disposable-host test scripts |
| [devsec.hardening](https://github.com/dev-sec/ansible-collection-hardening) | 10.6.0 | Maintained OS and SSH hardening roles | Apache-2.0 | Local implementation creates a larger security maintenance burden |
| [OpenTofu](https://github.com/opentofu/opentofu) | 1.12.6 | Infrastructure plan and apply interface | MPL-2.0 | Terraform compatibility may be checked, but apply remains OpenTofu-owned |
| [AWS provider](https://github.com/hashicorp/terraform-provider-aws) | 6.63.0 | Minimal EC2 bootstrap root | MPL-2.0 | A pre-existing Debian VM removes the AWS root |
| [Incus provider](https://github.com/lxc/terraform-provider-incus) | 1.2.0 | Later Incus substrate ownership | MPL-2.0 | Direct Incus API automation would need a new ownership contract |
| [Lima](https://github.com/lima-vm/lima) | 2.2.0 | Optional macOS disposable integration VM | Apache-2.0 | Skip Lima and test on the reference Debian VM |

Version changes require release-note review, updated locks, static validation,
and an explicit pull request. Cloud services may incur charges even though the
automation components are available without a license fee.

The transitive Ansible collections resolved by `devsec.hardening` are also
listed with exact versions in `ansible/requirements.yml`.

AWS CLI v2 is an operator-side integration client rather than a vendored or CI
dependency. Install the current v2 with Homebrew before a paid P1-04 session;
`make doctor` records the detected version. The live gates fail closed when the
Budgets or Price List commands are unavailable or unauthorized. A Free Tier
`ResourceNotFoundException` is recorded explicitly and means that planning
assumes no discount.

Mitogen is not included in the Phase 1 default. Its current release supports
the pinned Ansible generation, but relies on Ansible's deprecated third-party
strategy-plugin interface. One-host measurements must first show a meaningful
transport bottleneck before that extra runtime coupling is justified.
