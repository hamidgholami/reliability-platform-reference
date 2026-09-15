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

variable "platform_ipv4_cidr" {
  description = "Private /24 used by the Incus-managed platform bridge."
  type        = string
  default     = "10.20.0.0/24"

  validation {
    condition = (
      can(cidrhost(var.platform_ipv4_cidr, 199)) &&
      endswith(var.platform_ipv4_cidr, "/24") &&
      split("/", var.platform_ipv4_cidr)[0] == cidrhost(var.platform_ipv4_cidr, 0) &&
      (cidrcontains("10.0.0.0/8", cidrhost(var.platform_ipv4_cidr, 1)) ||
        cidrcontains("172.16.0.0/12", cidrhost(var.platform_ipv4_cidr, 1)) ||
      cidrcontains("192.168.0.0/16", cidrhost(var.platform_ipv4_cidr, 1)))
    )
    error_message = "platform_ipv4_cidr must be a canonical RFC1918 IPv4 /24."
  }
}

variable "platform_dns_domain" {
  description = "Private DNS suffix advertised by the managed bridge."
  type        = string
  default     = "dev.apadanalab.de"

  validation {
    condition = (
      length(var.platform_dns_domain) <= 253 &&
      can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.platform_dns_domain)) &&
      !strcontains(var.platform_dns_domain, "..")
    )
    error_message = "platform_dns_domain must be a lowercase DNS name without a trailing dot."
  }
}

variable "instance_image" {
  description = "Architecture-neutral remote image alias for the smoke container."
  type        = string
  default     = "images:debian/13"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+:[A-Za-z0-9][A-Za-z0-9_./-]*$", var.instance_image))
    error_message = "instance_image must be an explicit remote image alias."
  }
}
