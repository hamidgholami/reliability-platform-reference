# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

mock_provider "aws" {
  alias = "mock"

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-central-1a"]
    }
  }

  mock_data "aws_ami" {
    defaults = {
      architecture = "arm64"
      id           = "ami-00000000000000000"
      name         = "debian-13-arm64-test"
      owner_id     = "136693071363"
    }
  }
}

variables {
  created_at     = "2026-09-08T12:00:00Z"
  expires_at     = "2026-09-08T20:00:00Z"
  operator_cidr  = "192.0.2.1/32"
  owner          = "test-operator"
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyPublicKeyMaterial"
}

run "minimum_boundary" {
  command = plan

  providers = {
    aws = aws.mock
  }

  assert {
    condition     = aws_instance.incus_host.instance_type == "t4g.small"
    error_message = "The minimum path must start with t4g.small."
  }

  assert {
    condition     = aws_instance.incus_host.root_block_device[0].encrypted && aws_instance.incus_host.root_block_device[0].volume_size == 30 && aws_instance.incus_host.root_block_device[0].volume_type == "gp3"
    error_message = "The root volume must be an encrypted 30 GiB gp3 volume."
  }

  assert {
    condition     = aws_instance.incus_host.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 tokens must be required."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.ssh.cidr_ipv4 == var.operator_cidr && aws_vpc_security_group_ingress_rule.incus_api.cidr_ipv4 == var.operator_cidr
    error_message = "SSH and Incus API ingress must use only the selected operator CIDR."
  }
}

run "reject_world_open_cidr" {
  command = plan

  providers = {
    aws = aws.mock
  }

  variables {
    operator_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.operator_cidr]
}

run "reject_noncanonical_world_open_cidr" {
  command = plan

  providers = {
    aws = aws.mock
  }

  variables {
    operator_cidr = "10.20.30.40/0"
  }

  expect_failures = [var.operator_cidr]
}
