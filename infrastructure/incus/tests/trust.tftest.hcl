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
}

variables {
  deployment_profile = "workstation-validation"
  incus_config_dir   = "/tmp/test-incus-client"
  incus_remote       = "rpr-target"
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
