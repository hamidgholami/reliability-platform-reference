#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

output_file=$(mktemp)
fixture_dir=$(mktemp -d)
valid_fingerprint=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
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

expect_failure \
  "set CONFIRM=apply-incus-workstation-validation-rpr-target" \
  env PROFILE=workstation-validation INCUS_CONFIG_DIR=/tmp/incus-test \
  INCUS_REMOTE=rpr-target INCUS_ENDPOINT=https://127.0.0.1:18443 \
  INCUS_SERVER_CERTIFICATE_SHA256="$valid_fingerprint" \
  ./scripts/incus-substrate.sh apply

expect_failure \
  "set CONFIRM=destroy-incus-workstation-validation-rpr-target" \
  env PROFILE=workstation-validation INCUS_CONFIG_DIR=/tmp/incus-test \
  INCUS_REMOTE=rpr-target INCUS_ENDPOINT=https://127.0.0.1:18443 \
  INCUS_SERVER_CERTIFICATE_SHA256="$valid_fingerprint" \
  ./scripts/incus-substrate.sh destroy

mkdir -p "$fixture_dir/bin" "$fixture_dir/config/servercerts"
: >"$fixture_dir/config/config.yml"
: >"$fixture_dir/config/client.crt"
: >"$fixture_dir/config/client.key"
: >"$fixture_dir/config/servercerts/rpr-target.crt"

printf '%s\n' \
  '#!/usr/bin/env sh' \
  'case "$*" in' \
  '  "remote list --format json")' \
  '    printf '\''{"rpr-target":{"Addrs":["https://127.0.0.1:18443"]}}'\''' \
  '    ;;' \
  '  "query rpr-target:/1.0")' \
  '    if [ "${MOCK_INCUS_ENVELOPE:-}" = 1 ]; then' \
  '      printf '\''{"metadata":{"auth":"trusted","api_extensions":["projects_restrictions","projects_networks_restricted_access","projects_limits_disk_pool","storage_api_project"],"environment":{"server_clustered":false,"server_version":"6.0.4"}}}'\''' \
  '    else' \
  '      printf '\''{"auth":"trusted","api_extensions":["projects_restrictions","projects_networks_restricted_access","projects_limits_disk_pool","storage_api_project"],"environment":{"server_clustered":false,"server_version":"6.0.4"}}'\''' \
  '    fi' \
  '    ;;' \
  '  *) exit 1 ;;' \
  'esac' >"$fixture_dir/bin/incus"

printf '%s\n' \
  '#!/usr/bin/env sh' \
  'case "$*" in' \
  '  *"-fingerprint -sha256"*)' \
  '    echo "sha256 Fingerprint=AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA"' \
  '    ;;' \
  '  "x509 "*"-pubkey -noout") echo mock-public-key ;;' \
  '  "pkey -pubin -outform DER") sed '\''s/.*/mock-key-der/'\'' ;;' \
  '  "pkey -in "*" -pubout -outform DER") echo mock-key-der ;;' \
  '  "dgst -sha256") sed '\''s/.*/mock-key-digest/'\'' ;;' \
  '  *) exit 1 ;;' \
  'esac' >"$fixture_dir/bin/openssl"
chmod +x "$fixture_dir/bin/incus" "$fixture_dir/bin/openssl"

mkdir -p "$fixture_dir/cache"
printf '%s\n' '{}' >"$fixture_dir/cache/runtime.auto.tfvars.json"
mkdir -p "$fixture_dir/private-dns"
jq -n '{
  private_dns_tsig_secrets: {
    "dns-01": {
      forward: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      reverse: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    },
    "dns-02": {
      forward: "cccccccccccccccccccccccccccccccc",
      reverse: "dddddddddddddddddddddddddddddddd"
    }
  }
}' >"$fixture_dir/private-dns/tsig.auto.tfvars.json"
chmod 600 "$fixture_dir/private-dns/tsig.auto.tfvars.json"
private_dns_secrets_sha="$(shasum -a 256 \
  "$fixture_dir/private-dns/tsig.auto.tfvars.json" | awk '{print $1}')"
jq -n \
  --arg fingerprint "$valid_fingerprint" \
  --arg private_dns_secrets_file "$fixture_dir/private-dns/tsig.auto.tfvars.json" \
  --arg private_dns_secrets_sha "$private_dns_secrets_sha" '{
    deployment_profile: "workstation-validation",
    remote: "rpr-target",
    endpoint: "https://127.0.0.1:18443",
    server_certificate_sha256: $fingerprint,
    platform_ipv4_cidr: "10.20.0.0/24",
    platform_dns_domain: "dev.apadanalab.de",
    instance_image: "images:debian/13",
    private_dns_secrets_file: $private_dns_secrets_file,
    private_dns_secrets_sha256: $private_dns_secrets_sha,
    runtime_vars_sha256: "invalid"
  }' >"$fixture_dir/cache/session.json"

expect_failure \
  "planned Incus runtime inputs changed after review" \
  env PROFILE=workstation-validation \
  INCUS_CONFIG_DIR="$fixture_dir/config" \
  INCUS_REMOTE=rpr-target \
  INCUS_ENDPOINT=https://127.0.0.1:18443 \
  INCUS_SERVER_CERTIFICATE_SHA256="$valid_fingerprint" \
  PRIVATE_DNS_SECRETS_FILE="$fixture_dir/private-dns/tsig.auto.tfvars.json" \
  RPR_INCUS_CACHE_DIR="$fixture_dir/cache" \
  ./scripts/incus-substrate.sh validate

for response_shape in direct envelope; do
  if [ "$response_shape" = envelope ]; then
    envelope=1
  else
    envelope=
  fi

  PATH="$fixture_dir/bin:$PATH" \
    MOCK_INCUS_ENVELOPE="$envelope" \
    PROFILE=workstation-validation \
    INCUS_CONFIG_DIR="$fixture_dir/config" \
    INCUS_REMOTE=rpr-target \
    INCUS_ENDPOINT=https://127.0.0.1:18443 \
    INCUS_SERVER_CERTIFICATE_SHA256="$valid_fingerprint" \
    ./scripts/incus-substrate.sh preflight >"$output_file"
done

echo "Incus substrate safety checks passed."
