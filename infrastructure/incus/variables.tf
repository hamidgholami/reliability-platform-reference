# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

variable "deployment_profile" {
  description = "Explicit Phase 1 deployment profile."
  type        = string

  validation {
    condition = contains([
      "single-node-reference",
      "workstation-validation",
    ], var.deployment_profile)
    error_message = "Use single-node-reference or workstation-validation."
  }
}

variable "incus_config_dir" {
  description = "Absolute path to the pre-enrolled OpenTofu Incus client configuration."
  type        = string

  validation {
    condition     = startswith(var.incus_config_dir, "/")
    error_message = "incus_config_dir must be an absolute path."
  }
}

variable "incus_remote" {
  description = "Pre-enrolled Incus remote used by the provider."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", var.incus_remote))
    error_message = "incus_remote contains unsupported characters."
  }
}
