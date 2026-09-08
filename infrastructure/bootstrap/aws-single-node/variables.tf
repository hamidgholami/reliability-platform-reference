# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

variable "aws_region" {
  description = "AWS region in which to create the disposable reference host."
  type        = string
  default     = "eu-central-1"
}

variable "owner" {
  description = "Human owner recorded on every resource."
  type        = string

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner must not be empty."
  }
}

variable "created_at" {
  description = "Creation timestamp in RFC 3339 UTC form, supplied by the operator."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", var.created_at))
    error_message = "created_at must use RFC 3339 UTC form, for example 2026-09-08T12:00:00Z."
  }
}

variable "expires_at" {
  description = "Review or teardown deadline in RFC 3339 UTC form."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", var.expires_at))
    error_message = "expires_at must use RFC 3339 UTC form, for example 2026-09-08T20:00:00Z."
  }
}

variable "operator_cidr" {
  description = "IPv4 CIDR allowed to reach SSH and the Incus API. Never use 0.0.0.0/0."
  type        = string

  validation {
    condition = (
      can(cidrhost(var.operator_cidr, 0)) &&
      can(regex("^[0-9.]+/[0-9]+$", var.operator_cidr)) &&
      !can(regex("/0$", var.operator_cidr))
    )
    error_message = "operator_cidr must be a valid restricted IPv4 CIDR and cannot be 0.0.0.0/0."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH public key material used for the EC2 key pair."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com) ", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must be an Ed25519, ECDSA, or security-key OpenSSH public key."
  }
}

variable "instance_type" {
  description = "ARM64 instance type; increase only after recording a capacity failure."
  type        = string
  default     = "t4g.small"

  validation {
    condition     = contains(["t4g.small", "t4g.medium", "t4g.large"], var.instance_type)
    error_message = "instance_type must be one of the reviewed ARM64 t4g sizes."
  }
}

variable "vpc_cidr" {
  description = "Dedicated bootstrap VPC CIDR, separate from the Incus bridge range."
  type        = string
  default     = "10.40.0.0/24"
}

variable "subnet_cidr" {
  description = "Public subnet CIDR inside vpc_cidr."
  type        = string
  default     = "10.40.0.0/26"
}

variable "root_volume_size_gib" {
  description = "Encrypted gp3 root volume size in GiB."
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size_gib >= 30
    error_message = "root_volume_size_gib must be at least the reviewed 30 GiB baseline."
  }
}
