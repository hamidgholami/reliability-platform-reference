# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

locals {
  name = "rpr-single-node"
  common_tags = {
    Environment = "single-node-reference"
    ExpiresAt   = var.expires_at
    ManagedBy   = "OpenTofu"
    Owner       = var.owner
    Project     = "reliability-platform-reference"
    Purpose     = "disposable-incus-reference-host"
    CreatedAt   = var.created_at
  }
}

provider "aws" {
  allowed_account_ids = [var.aws_account_id]
  region              = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "debian_13_arm64" {
  most_recent = true
  owners      = ["136693071363"]

  filter {
    name   = "name"
    values = ["debian-13-arm64-*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "is-public"
    values = ["true"]
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "public" {
  availability_zone       = data.aws_availability_zones.available.names[0]
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.this.id

  tags = {
    Name = "${local.name}-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name}-public"
  }
}

resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public.id
}

resource "aws_security_group" "operator" {
  description = "Operator-only access to the disposable Incus host"
  name_prefix = "${local.name}-operator-"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${local.name}-operator"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  cidr_ipv4         = var.operator_cidr
  description       = "SSH from the selected operator network"
  from_port         = 22
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.operator.id
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "incus_api" {
  cidr_ipv4         = var.operator_cidr
  description       = "Incus API from the selected operator network"
  from_port         = 8443
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.operator.id
  to_port           = 8443
}

resource "aws_vpc_security_group_egress_rule" "ipv4" {
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Outbound package and image downloads"
  ip_protocol       = "-1"
  security_group_id = aws_security_group.operator.id
}

resource "aws_key_pair" "operator" {
  key_name_prefix = "${local.name}-"
  public_key      = trimspace(var.ssh_public_key)

  tags = {
    Name = "${local.name}-operator"
  }
}

resource "aws_instance" "incus_host" {
  ami                         = data.aws_ami.debian_13_arm64.id
  associate_public_ip_address = true
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.operator.key_name
  monitoring                  = false
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.operator.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.root_volume_size_gib
    volume_type           = "gp3"

    tags = merge(local.common_tags, {
      Name = "${local.name}-root"
    })
  }

  tags = {
    Name = local.name
  }

  lifecycle {
    precondition {
      condition     = timecmp(var.expires_at, var.created_at) > 0
      error_message = "expires_at must be later than created_at."
    }

    precondition {
      condition     = timecmp(var.expires_at, timeadd(var.created_at, "12h")) <= 0
      error_message = "the disposable reference VM lifetime cannot exceed 12 hours."
    }
  }

  depends_on = [aws_route_table_association.public]
}
