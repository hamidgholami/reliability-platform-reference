# Environment Profiles

Profiles describe intended capability and ownership, not identical topology.
Only `developer-validation` is expected to run continuously at first.

| Profile | Purpose | Foundation | Kubernetes | Cost posture |
| --- | --- | --- | --- | --- |
| `developer-validation` | Fast local validation | One Incus member | Small Kubespray cluster | Local-only by default |
| `onprem-reference` | Full local demonstration | Incus, non-HA or 3+ members | Kubespray | Explicit host capacity budget |
| `onprem-ha` | Failure-domain experiments | 3+ Incus members | HA control plane | Created only for scheduled tests |
| `aws-minimal` | Cloud interface validation | Minimal AWS primitives | Reused or compact cluster | TTL and budget required |
| `aws-eks-ephemeral` | Managed-Kubernetes comparison | AWS/EKS | Ephemeral EKS | Destroy deadline required |

Azure integrations may be introduced after the AWS profiles establish stable
interfaces. They are not a Phase 0 deployment commitment.

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
