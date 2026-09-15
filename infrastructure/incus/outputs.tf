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

output "substrate" {
  description = "Non-secret Phase 1 Incus substrate identity and runtime address."
  value = {
    project             = incus_project.development.name
    storage_pool        = incus_storage_pool.local.name
    network             = incus_network.platform.name
    bridge_ipv4_address = local.bridge_ipv4_address
    profile             = incus_profile.system.name
    instance            = incus_instance.smoke.name
    instance_type       = incus_instance.smoke.type
    instance_image      = var.instance_image
    instance_ipv4       = incus_instance.smoke.ipv4_address
    instance_dns_name   = local.instance_dns_name
    instance_status     = incus_instance.smoke.status
    ipv6_policy         = "disabled"
  }
}
