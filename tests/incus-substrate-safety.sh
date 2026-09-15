#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

output_file=$(mktemp)
valid_fingerprint=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
trap 'rm -f "$output_file"' EXIT HUP INT TERM

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
  "set PROFILE to workstation-validation or single-node-reference" \
  env PROFILE=invalid ./scripts/incus-substrate.sh preflight

expect_failure \
  "INCUS_CONFIG_DIR must be an absolute path" \
  env PROFILE=workstation-validation INCUS_CONFIG_DIR=relative \
  INCUS_REMOTE=rpr-target INCUS_ENDPOINT=https://127.0.0.1:18443 \
  INCUS_SERVER_CERTIFICATE_SHA256="$valid_fingerprint" \
  ./scripts/incus-substrate.sh preflight

expect_failure \
  "OpenTofu must not use the default human Incus client identity" \
  env PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$HOME/Library/Application Support/incus" \
  INCUS_REMOTE=rpr-target INCUS_ENDPOINT=https://127.0.0.1:18443 \
  INCUS_SERVER_CERTIFICATE_SHA256="$valid_fingerprint" \
  ./scripts/incus-substrate.sh preflight

expect_failure \
  "workstation-validation requires INCUS_ENDPOINT=https://127.0.0.1:18443" \
  env PROFILE=workstation-validation INCUS_CONFIG_DIR=/tmp/incus-test \
  INCUS_REMOTE=rpr-target INCUS_ENDPOINT=https://192.0.2.10:8443 \
  INCUS_SERVER_CERTIFICATE_SHA256="$valid_fingerprint" \
  ./scripts/incus-substrate.sh preflight

expect_failure \
  "INCUS_SERVER_CERTIFICATE_SHA256 must be one SHA-256 fingerprint" \
  env PROFILE=workstation-validation INCUS_CONFIG_DIR=/tmp/incus-test \
  INCUS_REMOTE=rpr-target INCUS_ENDPOINT=https://127.0.0.1:18443 \
  INCUS_SERVER_CERTIFICATE_SHA256=invalid \
  ./scripts/incus-substrate.sh preflight

echo "Incus substrate safety checks passed."
