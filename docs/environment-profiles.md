# Environment Profiles

Profiles describe intended capability and ownership, not identical topology.
The workstation is a control and test environment, not a continuously running
platform. Its Lima VM may be retained between development sessions and stopped
when idle, then recreated at clean acceptance boundaries.
`single-node-reference` is the first deployment-acceptance profile.

| Profile | Purpose | Foundation | Kubernetes | Cost posture |
| --- | --- | --- | --- | --- |
| `workstation-validation` | Fast checks and reusable local integration | One optional Lima VM, recreated at acceptance boundaries | None | Local and stopped when idle |
| `single-node-reference` | First deployable end-to-end increment | One Debian VM with standalone Incus; initially supplied by a minimal AWS root | Deferred to Phase 3 | Ephemeral, tagged, and measured |
| `onprem-reference` | Later expanded on-premises demonstration | Incus, non-HA or 3+ members | Kubespray | Explicit host capacity budget |
| `onprem-ha` | Failure-domain experiments | 3+ Incus members | HA control plane | Created only for scheduled tests |
| `aws-minimal` | Cloud interface validation | Minimal AWS primitives | Reused or compact cluster | TTL and budget required |
| `aws-eks-ephemeral` | Managed-Kubernetes comparison | AWS/EKS | Ephemeral EKS | Destroy deadline required |

Azure integrations may be introduced after the AWS profiles establish stable
interfaces. They are not a Phase 0 deployment commitment.

The initial AWS attempt uses `t4g.small` and 30 GiB encrypted `gp3`. It is a
minimum-cost experiment rather than a capacity promise. Scale only when the
active acceptance test records a resource failure. The profile uses Incus
system containers and does not require nested virtualization.

## Common contract

Every active profile must declare:

- owner, purpose, creation time, expiry/TTL, and estimated cost;
- DNS suffix and address allocation;
- identity and secret bootstrap route;
- data classification and backup destination;
- validation, recovery, and teardown commands;
- known differences from the reference architecture.

No `prod` profile exists today. The `prod.apadanalab.de` namespace is reserved
for a future environment and must not be presented as operational.
