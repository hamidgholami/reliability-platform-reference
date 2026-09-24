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
  "set CONFIRM=generate-private-dns-tsig-workstation-validation" \
  env PROFILE=workstation-validation CONFIRM= \
  ./scripts/private-dns-secrets.sh

touch "$fixture_dir/existing-secrets.json"
expect_failure \
  "refusing to overwrite existing private DNS secrets" \
  env PROFILE=workstation-validation \
  CONFIRM=generate-private-dns-tsig-workstation-validation \
  PRIVATE_DNS_SECRETS_FILE="$fixture_dir/existing-secrets.json" \
  ./scripts/private-dns-secrets.sh

expect_failure \
  "set CONFIRM=configure-private-dns-workstation-validation-rpr-target" \
  env PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/incus" \
  INCUS_REMOTE=rpr-target \
  CONFIRM= \
  ./scripts/private-dns.sh configure

expect_failure \
  "set CONFIRM=accept-private-dns-workstation-validation-rpr-target" \
  env PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/incus" \
  INCUS_REMOTE=rpr-target \
  PRIVATE_DNS_INVENTORY="$fixture_dir/inventory.json" \
  CONFIRM= \
  sh -c 'printf "{}\n" >"$PRIVATE_DNS_INVENTORY"; exec ./scripts/private-dns-acceptance.sh'

echo "Private DNS safety checks passed."
