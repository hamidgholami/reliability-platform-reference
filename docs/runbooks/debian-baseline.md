<!--
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
-->

# Debian 13 baseline runbook

This workflow prepares one explicitly selected Debian 13 host for standalone
Incus. It is a practical project baseline, not a claim of CIS compliance or
production hardening.

## Inputs and safety boundary

Copy the example inventory to an ignored file, replace the documentation
address, and set `debian_prepare_stable_target: true` only after confirming that
the address will remain valid through an SSH restart and reboot. Keep the
operator's private key outside this repository; provide only its matching public
key file to the workflow.

The baseline preserves the active inventory user as the operator, grants that
user passwordless sudo for automation, disables SSH password and root login,
and retains local-only SSH TCP forwarding. The pinned upstream hardening roles
apply the remaining policy. Explicit exceptions retain IPv4 forwarding,
SquashFS, AppArmor, and Incus-managed firewall behavior. The stricter upstream
setting that prevents arbitrary host users from creating user namespaces stays
enabled; validation instead confirms that the kernel namespace facility needed
by the privileged Incus daemon exists.

Export the same values for every command:

```shell
export PROFILE=single-node-reference
export INVENTORY=ansible/inventories/single-node-reference/hosts.local.yml
export TARGET_HOST=incus-reference-01
export OPERATOR_PUBLIC_KEY_FILE=/absolute/path/to/operator.pub
```

## Apply and prove the baseline

Run the non-mutating gate first:

```shell
make preflight
make baseline-check
```

Review the check-mode diff. Then use the exact confirmation printed by the
wrapper:

```shell
export CONFIRM=baseline-single-node-reference-incus-reference-01
make baseline
make validate-baseline
```

Run `make baseline` and `make validate-baseline` a second time. The second
baseline recap must report zero changed tasks. Validation writes a bounded JSON
report under the ignored `reports/p1-02/` directory and reports unexpected TCP
listeners; investigate any non-empty list before installing Incus.

## Recovery and rollback

Keep the original SSH session open while running the baseline. The upstream SSH
role validates the generated configuration, this playbook runs `sshd -t` again,
and only then applies the restart handler and proves a fresh authenticated
connection.

The first run preserves the original SSH configuration at
`/var/backups/reliability-platform-reference/sshd_config.pre-hardening`. If the
fresh connection check fails, use the still-open session or provider console to
restore that file, run `/usr/sbin/sshd -t`, and restart `ssh`. Package upgrades
are not automatically reversible; rebuild the disposable reference VM when
rollback would be less reliable than recreation.

Destroying the VM is outside this workflow. Use only the lifecycle command for
the provider that created it.

## Design references

- [Incus managed bridge behavior](https://linuxcontainers.org/incus/docs/main/reference/network_bridge/)
- [Incus firewall interaction](https://linuxcontainers.org/incus/docs/main/howto/network_bridge_firewalld/)
- [Incus user namespace and ID mapping](https://linuxcontainers.org/incus/docs/main/userns-idmap/)
- [`devsec.hardening` OS role variables](https://github.com/dev-sec/ansible-collection-hardening/blob/master/roles/os_hardening/README.md)
