# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

output "instance_id" {
  description = "Disposable reference host instance ID."
  value       = aws_instance.incus_host.id
}

output "public_ip" {
  description = "Temporary public IPv4 address used by the operator."
  value       = aws_instance.incus_host.public_ip
}

output "private_ip" {
  description = "Private address allocated inside the dedicated VPC."
  value       = aws_instance.incus_host.private_ip
}

output "ssh_user" {
  description = "Default user in the official Debian cloud image."
  value       = "admin"
}

output "selected_ami" {
  description = "Official Debian 13 arm64 AMI selected at plan time."
  value = {
    architecture = data.aws_ami.debian_13_arm64.architecture
    id           = data.aws_ami.debian_13_arm64.id
    name         = data.aws_ami.debian_13_arm64.name
    owner_id     = data.aws_ami.debian_13_arm64.owner_id
  }
}

output "declared_boundary" {
  description = "Resource classes intentionally created by this isolated root."
  value = [
    "one VPC and public subnet",
    "one internet gateway and route table",
    "one operator-restricted security group",
    "one EC2 key pair from supplied public material",
    "one EC2 instance with one encrypted gp3 root volume",
    "one temporary public IPv4 address",
  ]
}
