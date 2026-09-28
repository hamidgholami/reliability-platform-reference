#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

fixture_dir=$(mktemp -d)
output_file=$(mktemp)
trap 'rm -rf "$fixture_dir"; rm -f "$output_file"' EXIT HUP INT TERM

pki_dir="$fixture_dir/operator-pki"
passphrase=$(openssl rand -hex 24)

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
  "RPR_PKI_DIR must be an absolute path outside the repository" \
  env RPR_PKI_DIR=relative \
  ./scripts/openbao-pki.sh create

printf '%s\n%s\n' "$passphrase" "$passphrase" |
  env RPR_PKI_DIR="$pki_dir" \
  ./scripts/openbao-pki.sh create >"$output_file" 2>&1

[ -s "$pki_dir/root-ca/private/root-ca.key" ]
[ -s "$pki_dir/root-ca/index.txt" ]
[ -s "$pki_dir/root-ca/crl/root-ca.crl" ]
[ -s "$pki_dir/openbao-bootstrap/ca.crt" ]
[ -s "$pki_dir/openbao-bootstrap/ca.crl" ]
[ -s "$pki_dir/openbao-bootstrap/tls.crt" ]
[ -s "$pki_dir/openbao-bootstrap/tls.key" ]

RPR_PKI_DIR="$pki_dir" \
  ./scripts/validate-openbao-bootstrap-tls.sh >/dev/null

first_fingerprint=$(openssl x509 \
  -in "$pki_dir/openbao-bootstrap/tls.crt" \
  -noout -fingerprint -sha256)

expect_failure \
  "RPR_PKI_DIR already exists; refusing to overwrite root CA state" \
  env RPR_PKI_DIR="$pki_dir" \
  ./scripts/openbao-pki.sh create

printf '%s\n' "$passphrase" |
  env RPR_PKI_DIR="$pki_dir" \
  ./scripts/openbao-pki.sh renew >"$output_file" 2>&1

second_fingerprint=$(openssl x509 \
  -in "$pki_dir/openbao-bootstrap/tls.crt" \
  -noout -fingerprint -sha256)
[ "$first_fingerprint" != "$second_fingerprint" ]
[ "$(find "$pki_dir/archive" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = "1" ]

RPR_PKI_DIR="$pki_dir" \
  ./scripts/validate-openbao-bootstrap-tls.sh >/dev/null

intermediate_dir="$pki_dir/openbao-intermediate"
install -d -m 0700 "$intermediate_dir"
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:3072 \
  -out "$fixture_dir/synthetic-intermediate.key" >/dev/null 2>&1
printf '%s\n' \
  '[ req ]' \
  'prompt = no' \
  'distinguished_name = intermediate_dn' \
  'string_mask = nombstr' \
  '[ intermediate_dn ]' \
  'O = ApadanaLab' \
  'OU = Platform Trust' \
  'CN = ApadanaLab Online Intermediate CA' \
  >"$fixture_dir/printable-intermediate.cnf"
openssl req \
  -new \
  -sha384 \
  -key "$fixture_dir/synthetic-intermediate.key" \
  -config "$fixture_dir/printable-intermediate.cnf" \
  -out "$intermediate_dir/intermediate.csr.pem"
chmod 0600 "$intermediate_dir/intermediate.csr.pem"
openssl asn1parse \
  -in "$intermediate_dir/intermediate.csr.pem" \
  -inform PEM >"$fixture_dir/intermediate-asn1.txt"
grep -F 'PRINTABLESTRING   :ApadanaLab' \
  "$fixture_dir/intermediate-asn1.txt" >/dev/null

printf '%s\n' "$passphrase" |
  env RPR_PKI_DIR="$pki_dir" \
  ./scripts/openbao-pki.sh sign-intermediate >"$output_file" 2>&1

[ -s "$intermediate_dir/intermediate.crt" ]
[ -s "$intermediate_dir/chain.pem" ]
[ -s "$pki_dir/root-ca/requests/openbao-online-intermediate.csr" ]
[ "$(grep -c '^-----BEGIN CERTIFICATE-----$' "$intermediate_dir/chain.pem")" = "2" ]
openssl verify \
  -CAfile "$pki_dir/root-ca/certs/root-ca.crt" \
  "$intermediate_dir/intermediate.crt" >/dev/null
if grep -R -a -E -- '-----BEGIN .*PRIVATE KEY-----' "$intermediate_dir" >/dev/null; then
  echo "The intermediate handoff directory contains private-key material." >&2
  exit 1
fi

env RPR_PKI_DIR="$pki_dir" \
  ./scripts/openbao-pki.sh sign-intermediate >"$output_file" 2>&1
grep -F \
  "The existing OpenBao intermediate certificate and chain are valid." \
  "$output_file" >/dev/null

chmod 0644 "$pki_dir/openbao-bootstrap/tls.key"
expect_failure \
  "every OpenBao TLS input file must use mode 0600" \
  env RPR_PKI_DIR="$pki_dir" \
  ./scripts/validate-openbao-bootstrap-tls.sh

echo "Operator-managed root policy checks passed."
