# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

mock_provider "incus" {
  alias = "mock"

  mock_data "incus_cluster" {
    defaults = {
      is_clustered = false
      members      = {}
    }
  }

  mock_resource "incus_network" {
    defaults = {
      managed = true
    }
  }

  mock_resource "incus_instance" {
    defaults = {
      ipv4_address = "10.20.0.100"
      ipv6_address = ""
      mac_address  = "00:16:3e:00:00:01"
      status       = "Running"
    }
  }
}

variables {
  deployment_profile = "workstation-validation"
  incus_config_dir   = "/tmp/test-incus-client"
  incus_remote       = "rpr-target"
  private_dns_tsig_secrets = {
    dns-01 = {
      forward = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      reverse = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
    dns-02 = {
      forward = "cccccccccccccccccccccccccccccccc"
      reverse = "dddddddddddddddddddddddddddddddd"
    }
  }
}

run "trusted_standalone_boundary" {
  command = plan

  providers = {
    incus = incus.mock
  }

  assert {
    condition     = output.provider_trust_boundary.standalone
    error_message = "The Phase 1 provider target must be standalone."
  }

  assert {
    condition     = output.provider_trust_boundary.remote == "rpr-target"
    error_message = "The provider must use the explicitly selected remote."
  }

  assert {
    condition = (
      incus_project.development.config["restricted"] == "true" &&
      incus_project.development.config["limits.containers"] == "4" &&
      incus_project.development.config["limits.cpu"] == "4" &&
      incus_project.development.config["limits.disk"] == "12GiB" &&
      incus_project.development.config["limits.disk.pool.rpr-local"] == "12GiB" &&
      incus_project.development.config["limits.instances"] == "4" &&
      incus_project.development.config["limits.memory"] == "1536MiB" &&
      incus_project.development.config["limits.virtual-machines"] == "0"
    )
    error_message = "The development project must fit exactly four bounded containers and no VMs."
  }

  assert {
    condition = (
      incus_network.platform.config["ipv4.address"] == "10.20.0.1/24" &&
      incus_network.platform.config["ipv4.nat"] == "true" &&
      incus_network.platform.config["ipv6.address"] == "none"
    )
    error_message = "The managed bridge must use explicit IPv4 NAT and disabled IPv6."
  }

  assert {
    condition = (
      incus_network.platform.config["dns.zone.forward"] == incus_network_zone.forward.name &&
      incus_network.platform.config["dns.zone.reverse.ipv4"] == incus_network_zone.reverse.name &&
      length(incus_instance.dns) == 2 &&
      incus_instance.dns["dns-01"].type == "container" &&
      incus_instance.dns["dns-02"].type == "container"
    )
    error_message = "Private DNS must use two bounded containers attached to the Incus-owned zones."
  }

  assert {
    condition     = incus_storage_pool.local.driver == "dir"
    error_message = "Phase 1 must use the portable local dir storage driver."
  }

  assert {
    condition = (
      incus_instance.smoke.type == "container" &&
      length(incus_instance.smoke.profiles) == 1 &&
      incus_instance.smoke.profiles[0] == incus_profile.system.name
    )
    error_message = "The smoke workload must be a system container using only the managed profile."
  }

  assert {
    condition = (
      incus_profile.openbao.config["limits.cpu"] == "1" &&
      incus_profile.openbao.config["limits.memory"] == "512MiB" &&
      incus_profile.openbao.config["security.nesting"] == "false" &&
      incus_profile.openbao.config["security.privileged"] == "false" &&
      one([
        for device in incus_profile.openbao.device : device
        if device.name == "root"
      ]).properties["size"] == "4GiB" &&
      one([
        for device in incus_profile.openbao.device : device
        if device.name == "root"
      ]).properties["pool"] == incus_storage_pool.local.name
    )
    error_message = "The OpenBao profile must retain the reviewed CPU, memory, disk, and isolation limits."
  }

  assert {
    condition = (
      incus_instance.openbao.name == "bao-01" &&
      incus_instance.openbao.type == "container" &&
      length(incus_instance.openbao.profiles) == 1 &&
      incus_instance.openbao.profiles[0] == incus_profile.openbao.name &&
      one(incus_instance.openbao.device).properties["ipv4.address"] == "10.20.0.20" &&
      one(incus_instance.openbao.device).properties["security.acls"] == incus_network_acl.openbao.name &&
      one(incus_instance.openbao.device).properties["security.acls.default.ingress.action"] == "reject" &&
      one(incus_instance.openbao.device).properties["security.acls.default.egress.action"] == "allow"
    )
    error_message = "OpenBao must be one bounded container with a static address and fail-closed ingress ACL."
  }

  assert {
    condition = (
      incus_network_acl.openbao.project == "default" &&
      length(incus_network_acl.openbao.ingress) == 1 &&
      length(incus_network_acl.openbao.egress) == 0 &&
      one(incus_network_acl.openbao.ingress).action == "allow" &&
      one(incus_network_acl.openbao.ingress).source == "10.20.0.0/24" &&
      one(incus_network_acl.openbao.ingress).destination == "10.20.0.20" &&
      one(incus_network_acl.openbao.ingress).destination_port == "8200" &&
      one(incus_network_acl.openbao.ingress).protocol == "tcp" &&
      one(incus_network_acl.openbao.ingress).state == "enabled"
    )
    error_message = "The host ACL must allow only the private platform CIDR to reach the OpenBao API port."
  }

  assert {
    condition = (
      incus_network_zone_record.openbao.name == "openbao" &&
      one(incus_network_zone_record.openbao.entry).type == "CNAME" &&
      one(incus_network_zone_record.openbao.entry).value == "bao-01.dev.apadanalab.de." &&
      output.openbao_foundation.alias_name == "openbao.dev.apadanalab.de"
    )
    error_message = "The private OpenBao alias must target the Incus-generated service name."
  }
}

run "reject_relative_client_config" {
  command = plan

  providers = {
    incus = incus.mock
  }

  variables {
    incus_config_dir = "relative/path"
  }

  expect_failures = [var.incus_config_dir]
}

run "reject_invalid_remote_name" {
  command = plan

  providers = {
    incus = incus.mock
  }

  variables {
    incus_remote = "rpr target"
  }

  expect_failures = [var.incus_remote]
}

run "reject_noncanonical_bridge_subnet" {
  command = plan

  providers = {
    incus = incus.mock
  }

  variables {
    platform_ipv4_cidr = "10.20.0.1/24"
  }

  expect_failures = [var.platform_ipv4_cidr]
}

run "reject_public_bridge_subnet" {
  command = plan

  providers = {
    incus = incus.mock
  }

  variables {
    platform_ipv4_cidr = "203.0.113.0/24"
  }

  expect_failures = [var.platform_ipv4_cidr]
}

run "reject_implicit_image_source" {
  command = plan

  providers = {
    incus = incus.mock
  }

  variables {
    instance_image = "debian/13"
  }

  expect_failures = [var.instance_image]
}
