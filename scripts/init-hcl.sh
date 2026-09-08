#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

for root in infrastructure/bootstrap/aws-single-node infrastructure/incus; do
  echo "Initializing locked providers for ${root}"
  tofu -chdir="$root" init -backend=false -input=false -lockfile=readonly
done
