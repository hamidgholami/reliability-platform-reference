# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

# This data source proves provider authentication before any resource action.
data "incus_cluster" "target" {
  remote = var.incus_remote
}

check "standalone_target" {
  assert {
    condition     = !data.incus_cluster.target.is_clustered
    error_message = "Phase 1 supports only a standalone Incus target."
  }
}

locals {
  project_name      = "rpr-dev"
  storage_pool_name = "rpr-local"
  network_name      = "platform0"
  profile_name      = "system-container"
  instance_name     = "smoke-01"

  bridge_ipv4_address = "${cidrhost(var.platform_ipv4_cidr, 1)}/${split("/", var.platform_ipv4_cidr)[1]}"
  dhcp_ipv4_range     = "${cidrhost(var.platform_ipv4_cidr, 120)}-${cidrhost(var.platform_ipv4_cidr, 219)}"
  instance_dns_name   = "${local.instance_name}.${var.platform_dns_domain}"
}

resource "incus_storage_pool" "local" {
  name        = local.storage_pool_name
  description = "Local Phase 1 system-container storage"
  driver      = "dir"
  project     = "default"
  remote      = var.incus_remote
}

resource "incus_network" "platform" {
  name        = local.network_name
  description = "Managed Phase 1 bridge with DHCP, DNS, and NAT"
  type        = "bridge"
  project     = "default"
  remote      = var.incus_remote

  config = {
    "dns.domain"       = var.platform_dns_domain
    "dns.mode"         = "managed"
    "dns.search"       = var.platform_dns_domain
    "ipv4.address"     = local.bridge_ipv4_address
    "ipv4.dhcp"        = "true"
    "ipv4.dhcp.ranges" = local.dhcp_ipv4_range
    "ipv4.firewall"    = "true"
    "ipv4.nat"         = "true"
    "ipv6.address"     = "none"
  }
}

resource "incus_project" "development" {
  name          = local.project_name
  description   = "Restricted Phase 1 development project"
  force_destroy = false
  remote        = var.incus_remote

  config = {
    "features.images"                                   = "false"
    "features.networks"                                 = "false"
    "features.networks.zones"                           = "false"
    "features.profiles"                                 = "true"
    "features.storage.buckets"                          = "false"
    "features.storage.volumes"                          = "true"
    "limits.containers"                                 = "1"
    "limits.cpu"                                        = "1"
    "limits.disk"                                       = "4GiB"
    "limits.disk.pool.${incus_storage_pool.local.name}" = "4GiB"
    "limits.instances"                                  = "1"
    "limits.memory"                                     = "512MiB"
    "limits.virtual-machines"                           = "0"
    "restricted"                                        = "true"
    "restricted.devices.disk"                           = "managed"
    "restricted.devices.nic"                            = "managed"
    "restricted.networks.access"                        = incus_network.platform.name
  }
}

resource "incus_profile" "system" {
  name        = local.profile_name
  description = "Bounded unprivileged Phase 1 system container"
  project     = incus_project.development.name
  remote      = var.incus_remote

  config = {
    "boot.autostart"      = "true"
    "limits.cpu"          = "1"
    "limits.memory"       = "512MiB"
    "security.nesting"    = "false"
    "security.privileged" = "false"
  }

  device {
    name = "root"
    type = "disk"

    properties = {
      path = "/"
      pool = incus_storage_pool.local.name
      size = "4GiB"
    }
  }

  device {
    name = "eth0"
    type = "nic"

    properties = {
      name    = "eth0"
      network = incus_network.platform.name
    }
  }
}

resource "incus_instance" "smoke" {
  name        = local.instance_name
  description = "Disposable Phase 1 connectivity and lifecycle probe"
  image       = var.instance_image
  type        = "container"
  ephemeral   = false
  running     = true
  profiles    = [incus_profile.system.name]
  project     = incus_project.development.name
  remote      = var.incus_remote

  config = {
    "user.access_interface" = "eth0"
  }

  wait_for {
    type = "ipv4"
    nic  = "eth0"
  }
}
