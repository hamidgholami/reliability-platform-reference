# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

output "provider_trust_boundary" {
  description = "Non-secret result of the read-only provider trust check."
  value = {
    deployment_profile = var.deployment_profile
    remote             = var.incus_remote
    standalone         = !data.incus_cluster.target.is_clustered
  }
}
