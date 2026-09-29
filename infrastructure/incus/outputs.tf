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

output "private_dns" {
  description = "Non-secret private DNS topology and service addresses."
  value = {
    primary_address = cidrhost(var.platform_ipv4_cidr, 1)
    primary_port    = 1053
    forward_zone    = incus_network_zone.forward.name
    reverse_zone    = incus_network_zone.reverse.name
    resolver_name   = "resolver.${var.platform_dns_domain}"
    profile         = incus_profile.dns.name
    secondaries = {
      for name, instance in incus_instance.dns : name => {
        ipv4_address = instance.ipv4_address
        dns_name     = "${name}.${var.platform_dns_domain}"
        status       = instance.status
      }
    }
  }
}

output "openbao_foundation" {
  description = "Non-secret OpenBao service substrate and private endpoint."
  value = {
    profile       = incus_profile.openbao.name
    instance      = incus_instance.openbao.name
    instance_type = incus_instance.openbao.type
    ipv4_address  = incus_instance.openbao.ipv4_address
    dns_name      = local.openbao_dns_name
    alias_name    = local.openbao_alias_name
    api_port      = 8200
    network_acl   = incus_network_acl.openbao.name
    status        = incus_instance.openbao.status
  }
}

output "postgresql_service" {
  description = "Non-secret PostgreSQL service placement and private endpoint."
  value = {
    profile       = incus_profile.postgresql.name
    instance      = incus_instance.postgresql.name
    instance_type = incus_instance.postgresql.type
    ipv4_address  = incus_instance.postgresql.ipv4_address
    dns_name      = "${local.postgresql_instance_name}.${var.platform_dns_domain}"
    port          = 5432
    network_acl   = incus_network_acl.postgresql.name
    status        = incus_instance.postgresql.status
  }
}

output "ssh_test_service" {
  description = "Non-secret disposable SSH certificate target."
  value = var.ssh_test_enabled ? {
    profile       = incus_profile.ssh_test[0].name
    instance      = incus_instance.ssh_test[0].name
    instance_type = incus_instance.ssh_test[0].type
    ipv4_address  = incus_instance.ssh_test[0].ipv4_address
    dns_name      = "${local.ssh_test_instance_name}.${var.platform_dns_domain}"
    port          = 22
    network_acl   = incus_network_acl.ssh_test[0].name
    status        = incus_instance.ssh_test[0].status
  } : null
}
