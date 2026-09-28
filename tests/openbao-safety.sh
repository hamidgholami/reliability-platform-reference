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

mkdir -p "$fixture_dir/pki"
expect_failure \
  "set CONFIRM=initialize-openbao-workstation-validation-rpr-target" \
  env PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/incus" \
  INCUS_REMOTE=rpr-target \
  RPR_PKI_DIR="$fixture_dir/pki" \
  CONFIRM= \
  ./scripts/openbao-ceremony.sh initialize

expect_failure \
  "OPENBAO_RECOVERY_DIR must remain outside the repository" \
  env PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/incus" \
  INCUS_REMOTE=rpr-target \
  RPR_PKI_DIR="$fixture_dir/pki" \
  OPENBAO_RECOVERY_DIR="$PWD/.cache/test-openbao-recovery" \
  CONFIRM=initialize-openbao-workstation-validation-rpr-target \
  ./scripts/openbao-ceremony.sh initialize

jq -n '{
  all: {
    children: {
      openbao_service: {
        vars: {
          rpr_deployment_profile: "workstation-validation",
          ansible_incus_remote: "rpr-target",
          ansible_incus_project: "rpr-dev",
          openbao_platform_cidr: "10.20.0.0/24",
          openbao_api_address: "10.20.0.20",
          openbao_api_port: 8200,
          openbao_api_dns_name: "openbao.dev.apadanalab.de"
        },
        hosts: {
          "bao-01": {ansible_host: "bao-01"}
        }
      }
    }
  }
}' >"$fixture_dir/valid-inventory.json"
mkdir -p "$fixture_dir/incus" "$fixture_dir/mock-state"
recovery_dir="$fixture_dir/pki/openbao-recovery"
passphrase=synthetic-recovery-passphrase
mock_path="$PWD/tests/fixtures/openbao-ceremony:$PATH"

if ! printf '%s\n%s\n' "$passphrase" "$passphrase" |
  env PATH="$mock_path" \
  MOCK_INCUS_STATE_DIR="$fixture_dir/mock-state" \
  PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/incus" \
  INCUS_REMOTE=rpr-target \
  RPR_PKI_DIR="$fixture_dir/pki" \
  OPENBAO_INVENTORY="$fixture_dir/valid-inventory.json" \
  CONFIRM=initialize-openbao-workstation-validation-rpr-target \
  ./scripts/openbao-ceremony.sh initialize >"$output_file" 2>&1; then
  cat "$output_file" >&2
  exit 1
fi

[ -s "$recovery_dir/initialization.json" ]
[ -s "$recovery_dir/recovery-public.gpg" ]
[ -s "$recovery_dir/recovery-secret.gpg" ]
[ "$(find "$recovery_dir" -prune -type d -perm 0700 -print)" = "$recovery_dir" ]
for protected_file in initialization.json recovery-public.gpg recovery-secret.gpg; do
  protected_path="$recovery_dir/$protected_file"
  [ "$(find "$protected_path" -prune -type f -perm 0600 -print)" = "$protected_path" ]
done
if grep -R -a -E \
  'synthetic-(unseal-share|initial-root-token)|synthetic-recovery-passphrase' \
  "$recovery_dir" "$output_file" >/dev/null; then
  echo "OpenBao ceremony exposed synthetic secret material." >&2
  exit 1
fi

if ! printf '%s\n' "$passphrase" |
  env PATH="$mock_path" \
  MOCK_INCUS_STATE_DIR="$fixture_dir/mock-state" \
  PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/incus" \
  INCUS_REMOTE=rpr-target \
  RPR_PKI_DIR="$fixture_dir/pki" \
  OPENBAO_INVENTORY="$fixture_dir/valid-inventory.json" \
  CONFIRM=unseal-openbao-workstation-validation-rpr-target \
  ./scripts/openbao-ceremony.sh unseal >"$output_file" 2>&1; then
  cat "$output_file" >&2
  exit 1
fi
[ -f "$fixture_dir/mock-state/unsealed" ]

rm -f "$fixture_dir/mock-state/initialized" "$fixture_dir/mock-state/unsealed"
expect_failure \
  "refusing to overwrite existing OpenBao recovery material" \
  env PATH="$mock_path" \
  MOCK_INCUS_STATE_DIR="$fixture_dir/mock-state" \
  PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/incus" \
  INCUS_REMOTE=rpr-target \
  RPR_PKI_DIR="$fixture_dir/pki" \
  OPENBAO_INVENTORY="$fixture_dir/valid-inventory.json" \
  CONFIRM=initialize-openbao-workstation-validation-rpr-target \
  ./scripts/openbao-ceremony.sh initialize

echo "OpenBao safety checks passed."
