#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

output_file=$(mktemp)
fixture_dir=$(mktemp -d)
trap 'rm -f "$output_file"; rm -rf "$fixture_dir"' EXIT HUP INT TERM

expect_failure()
{
  expected_message=$1
  shift

  if "$@" >"$output_file" 2>&1; then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi

  if ! grep -F "$expected_message" "$output_file" >/dev/null; then
    echo "Missing expected failure message: $expected_message" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

expect_failure \
  "set CONFIRM=configure-openbao-workstation-validation-rpr-target" \
  env PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/incus" \
  INCUS_REMOTE=rpr-target \
  CONFIRM= \
  ./scripts/openbao.sh configure

expect_failure \
  "OPENBAO_TLS_INPUT_DIR must be an absolute protected directory" \
  env PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/incus" \
  INCUS_REMOTE=rpr-target \
  CONFIRM=configure-openbao-workstation-validation-rpr-target \
  OPENBAO_TLS_INPUT_DIR=relative \
  ./scripts/openbao.sh configure

expect_failure \
  "OpenBao inventory is missing; run make apply" \
  env PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/incus" \
  INCUS_REMOTE=rpr-target \
  OPENBAO_INVENTORY="$fixture_dir/missing.json" \
  ./scripts/openbao.sh status

printf '{}\n' >"$fixture_dir/inventory.json"
expect_failure \
  "OpenBao inventory violates the reviewed boundary" \
  env PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/incus" \
  INCUS_REMOTE=rpr-target \
  OPENBAO_INVENTORY="$fixture_dir/inventory.json" \
  ./scripts/openbao.sh status

echo "OpenBao safety checks passed."
