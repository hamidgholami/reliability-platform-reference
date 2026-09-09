#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

output_file=$(mktemp)
trap 'rm -f "$output_file"' EXIT HUP INT TERM

expect_failure() {
  expected_message=$1
  shift

  if "$@" >"$output_file" 2>&1; then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi

  if ! grep -F "$expected_message" "$output_file" >/dev/null; then
    echo "Missing expected failure message: $expected_message" >&2
    exit 1
  fi
}

expect_failure \
  "set PROFILE to single-node-reference or workstation-validation" \
  env PROFILE=invalid ./scripts/ansible-target.sh baseline

expect_failure \
  "TARGET_HOST contains unsupported characters" \
  env PROFILE=single-node-reference \
  INVENTORY=ansible/inventories/single-node-reference/hosts.example.yml \
  TARGET_HOST='incus-reference-01;unsafe' \
  OPERATOR_PUBLIC_KEY_FILE=/dev/null \
  ./scripts/ansible-target.sh baseline

expect_failure \
  "set CONFIRM=baseline-single-node-reference-incus-reference-01" \
  env PROFILE=single-node-reference \
  INVENTORY=ansible/inventories/single-node-reference/hosts.example.yml \
  TARGET_HOST=incus-reference-01 \
  OPERATOR_PUBLIC_KEY_FILE=/dev/null \
  CONFIRM= \
  ./scripts/ansible-target.sh baseline

echo "Ansible target safety checks passed."
