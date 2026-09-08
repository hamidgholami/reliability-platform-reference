# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "1.2.0"
    }
  }
}
