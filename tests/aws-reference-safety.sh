#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

output_file=$(mktemp)
public_key_file=$(mktemp)
cache_dir=$(mktemp -d)
trap 'rm -f "$output_file" "$public_key_file"; rm -rf "$cache_dir"' EXIT HUP INT TERM

printf '%s\n' 'ssh-ed25519 invalid-test-material' >"$public_key_file"

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
  "set PROFILE=single-node-reference" \
  env PROFILE=invalid ./scripts/aws-reference.sh plan

expect_failure \
  "OPERATOR_CIDR must be one public IPv4 /32" \
  env PROFILE=single-node-reference AWS_PROFILE=test AWS_BUDGET_NAME=test \
  OWNER=test OPERATOR_CIDR=192.0.2.0/24 \
  OPERATOR_PUBLIC_KEY_FILE="$public_key_file" TTL_HOURS=2 \
  RPR_AWS_CACHE_DIR="$cache_dir" ./scripts/aws-reference.sh plan

expect_failure \
  "TTL_HOURS must be an integer from 1 through 12" \
  env PROFILE=single-node-reference AWS_PROFILE=test AWS_BUDGET_NAME=test \
  OWNER=test OPERATOR_CIDR=192.0.2.1/32 \
  OPERATOR_PUBLIC_KEY_FILE="$public_key_file" TTL_HOURS=24 \
  RPR_AWS_CACHE_DIR="$cache_dir" ./scripts/aws-reference.sh plan

jq -n '{
  schema_version: 1,
  aws_profile: "test",
  account_id: "123456789012",
  aws_region: "eu-central-1",
  expires_at: "2099-01-01T00:00:00Z"
}' >"$cache_dir/session.json"
printf '%s\n' '{}' >"$cache_dir/runtime.auto.tfvars.json"

expect_failure \
  "set CONFIRM=aws-apply-single-node-reference-123456789012" \
  env PROFILE=single-node-reference AWS_PROFILE=test \
  RPR_AWS_CACHE_DIR="$cache_dir" ./scripts/aws-reference.sh apply

expect_failure \
  "set CONFIRM=aws-destroy-single-node-reference-123456789012" \
  env PROFILE=single-node-reference AWS_PROFILE=test \
  RPR_AWS_CACHE_DIR="$cache_dir" ./scripts/aws-reference.sh destroy

echo "AWS reference lifecycle safety checks passed."
