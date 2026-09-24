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
  dns_profile_name  = "dns-secondary"

  bridge_ipv4_address      = "${cidrhost(var.platform_ipv4_cidr, 1)}/${split("/", var.platform_ipv4_cidr)[1]}"
  dhcp_ipv4_range          = "${cidrhost(var.platform_ipv4_cidr, 120)}-${cidrhost(var.platform_ipv4_cidr, 219)}"
  instance_dns_name        = "${local.instance_name}.${var.platform_dns_domain}"
  reverse_zone_name        = join(".", reverse(slice(split(".", cidrhost(var.platform_ipv4_cidr, 0)), 0, 3)))
  private_dns_reverse_zone = "${local.reverse_zone_name}.in-addr.arpa"
  private_dns_secondaries = {
    dns-01 = cidrhost(var.platform_ipv4_cidr, 10)
    dns-02 = cidrhost(var.platform_ipv4_cidr, 11)
  }
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
    "dns.domain"            = var.platform_dns_domain
    "dns.mode"              = "managed"
    "dns.search"            = var.platform_dns_domain
    "dns.zone.forward"      = incus_network_zone.forward.name
    "dns.zone.reverse.ipv4" = incus_network_zone.reverse.name
    "ipv4.address"          = local.bridge_ipv4_address
    "ipv4.dhcp"             = "true"
    "ipv4.dhcp.ranges"      = local.dhcp_ipv4_range
    "ipv4.firewall"         = "true"
    "ipv4.nat"              = "true"
    "ipv6.address"          = "none"
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
    "features.networks.zones"                           = "true"
    "features.profiles"                                 = "true"
    "features.storage.buckets"                          = "false"
    "features.storage.volumes"                          = "true"
    "limits.containers"                                 = "3"
    "limits.cpu"                                        = "3"
    "limits.disk"                                       = "8GiB"
    "limits.disk.pool.${incus_storage_pool.local.name}" = "8GiB"
    "limits.instances"                                  = "3"
    "limits.memory"                                     = "1GiB"
    "limits.virtual-machines"                           = "0"
    "restricted"                                        = "true"
    "restricted.devices.disk"                           = "managed"
    "restricted.devices.nic"                            = "managed"
    "restricted.networks.access"                        = local.network_name
    "restricted.networks.zones"                         = "${var.platform_dns_domain},${local.private_dns_reverse_zone}"
  }
}

resource "incus_network_zone" "forward" {
  name        = var.platform_dns_domain
  description = "Private forward zone generated from Incus state"
  project     = incus_project.development.name
  remote      = var.incus_remote

  config = merge(
    {
      "dns.nameservers" = join(",", [
        for name in sort(keys(local.private_dns_secondaries)) :
        "${name}.${var.platform_dns_domain}"
      ])
      "network.nat" = "true"
    },
    {
      for name, address in local.private_dns_secondaries :
      "peers.${name}.address" => address
    },
    {
      for name, secrets in var.private_dns_tsig_secrets :
      "peers.${name}.key" => secrets.forward
    }
  )
}

resource "incus_network_zone" "reverse" {
  name        = local.private_dns_reverse_zone
  description = "Private IPv4 reverse zone generated from Incus state"
  project     = incus_project.development.name
  remote      = var.incus_remote

  config = merge(
    {
      "dns.nameservers" = join(",", [
        for name in sort(keys(local.private_dns_secondaries)) :
        "${name}.${var.platform_dns_domain}"
      ])
      "network.nat" = "true"
    },
    {
      for name, address in local.private_dns_secondaries :
      "peers.${name}.address" => address
    },
    {
      for name, secrets in var.private_dns_tsig_secrets :
      "peers.${name}.key" => secrets.reverse
    }
  )
}

resource "incus_network_zone_record" "resolver" {
  name        = "resolver"
  description = "Stable private resolver record managed by OpenTofu"
  zone        = incus_network_zone.forward.name
  project     = incus_project.development.name
  remote      = var.incus_remote

  dynamic "entry" {
    for_each = local.private_dns_secondaries

    content {
      type  = "A"
      value = entry.value
      ttl   = 300
    }
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

resource "incus_profile" "dns" {
  name        = local.dns_profile_name
  description = "Bounded unprivileged authoritative DNS secondary"
  project     = incus_project.development.name
  remote      = var.incus_remote

  config = {
    "boot.autostart"      = "true"
    "limits.cpu"          = "1"
    "limits.memory"       = "256MiB"
    "security.nesting"    = "false"
    "security.privileged" = "false"
  }

  device {
    name = "root"
    type = "disk"

    properties = {
      path = "/"
      pool = incus_storage_pool.local.name
      size = "2GiB"
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

resource "incus_instance" "dns" {
  for_each = local.private_dns_secondaries

  name        = each.key
  description = "Private authoritative BIND secondary"
  image       = var.instance_image
  type        = "container"
  ephemeral   = false
  running     = true
  profiles    = [incus_profile.dns.name]
  project     = incus_project.development.name
  remote      = var.incus_remote

  config = {
    "user.access_interface" = "eth0"
  }

  device {
    name = "eth0"
    type = "nic"

    properties = {
      name           = "eth0"
      network        = incus_network.platform.name
      "ipv4.address" = each.value
    }
  }

  wait_for {
    type = "ipv4"
    nic  = "eth0"
  }
}
