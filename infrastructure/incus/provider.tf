# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

provider "incus" {
  config_dir                   = var.incus_config_dir
  default_remote               = var.incus_remote
  generate_client_certificates = false
  accept_remote_certificate    = false
}
