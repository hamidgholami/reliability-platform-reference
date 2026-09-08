#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

for root in infrastructure/bootstrap/aws-single-node infrastructure/incus; do
  echo "Validating ${root}"
  tofu -chdir="$root" validate
done
