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
| [Mitogen](https://github.com/mitogen-hq/mitogen) | 0.3.53 | Accelerated Ansible transport for Python-backed target plays | BSD-3-Clause | Use Ansible's built-in linear strategy with higher per-task overhead |
| [devsec.hardening](https://github.com/dev-sec/ansible-collection-hardening) | 10.6.0 | Maintained OS and SSH hardening roles | Apache-2.0 | Local implementation creates a larger security maintenance burden |
| [OpenTofu](https://github.com/opentofu/opentofu) | 1.12.6 | Infrastructure plan and apply interface | MPL-2.0 | Terraform compatibility may be checked, but apply remains OpenTofu-owned |
| [AWS provider](https://github.com/hashicorp/terraform-provider-aws) | 6.63.0 | Minimal EC2 bootstrap root | MPL-2.0 | A pre-existing Debian VM removes the AWS root |
| [Incus provider](https://github.com/lxc/terraform-provider-incus) | 1.2.0 | Later Incus substrate ownership | MPL-2.0 | Direct Incus API automation would need a new ownership contract |
| [Lima](https://github.com/lima-vm/lima) | 2.2.0 | Optional macOS disposable integration VM | Apache-2.0 | Skip Lima and test on the reference Debian VM |

Version changes require release-note review, updated locks, static validation,
and an explicit pull request. Cloud services may incur charges even though the
automation components are available without a license fee.

The transitive Ansible collections resolved by `devsec.hardening` are also
listed with exact versions in `ansible/requirements.yml`. The pinned
`ansible.posix` collection supplies the operational `profile_tasks` callback;
target runs report the twenty slowest tasks so performance changes are based on
measurements rather than total wall time alone.

AWS CLI v2 is an operator-side integration client rather than a vendored or CI
dependency. Install the current v2 with Homebrew before a paid P1-04 session;
`make doctor` records the detected version. The live gates fail closed when the
Budgets or Price List commands are unavailable or unauthorized. A Free Tier
`ResourceNotFoundException` is recorded explicitly and means that planning
assumes no discount.

Mitogen is enabled by the repository's operational SSH-target wrapper after a
one-host baseline check fell from 54.20 seconds to 10.83 seconds, about five
times faster. Plays that must bootstrap or validate Python explicitly retain
Ansible's built-in `linear` strategy. The Incus-container wrapper also retains
the built-in strategy because its fully qualified connection plug-in is outside
the measured SSH path. Mitogen still relies on Ansible's deprecated third-party
strategy-plugin interface, so Ansible upgrades require a compatibility review.
Set `ANSIBLE_STRATEGY=linear` on an operational target command for the bounded
rollback path.

## Phase 2 runtime packages

P2-01 installs `bind9` and `bind9-dnsutils` from the Debian 13 stable/security
repositories. Automation accepts only the BIND 9.20 package line so Debian
security revisions remain installable without silently crossing a feature
series. Deployment acceptance records the exact installed revision.
