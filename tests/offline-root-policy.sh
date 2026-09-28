#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

fixture_dir=$(mktemp -d)
output_file=$(mktemp)
trap 'rm -rf "$fixture_dir"; rm -f "$output_file"' EXIT HUP INT TERM

root_dir="$fixture_dir/root"
tls_dir="$fixture_dir/tls"
passphrase_file="$fixture_dir/root-passphrase"

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
  "OPENBAO_TLS_INPUT_DIR must be an absolute protected directory" \
  env OPENBAO_TLS_INPUT_DIR=relative \
  ./scripts/validate-openbao-bootstrap-tls.sh

install -d -m 0700 \
  "$root_dir/certs" "$root_dir/crl" "$root_dir/newcerts" \
  "$root_dir/private" "$tls_dir"
install -m 0600 pki/offline-root/root-ca.cnf "$root_dir/root-ca.cnf"
: >"$root_dir/index.txt"
printf '1000\n' >"$root_dir/serial"
printf '1000\n' >"$root_dir/crlnumber"
openssl rand -hex 24 >"$passphrase_file"
chmod 0600 "$passphrase_file"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -aes-256-cbc -pass file:"$passphrase_file" \
  -out "$root_dir/private/root-ca.key" >/dev/null 2>&1

(
  cd "$root_dir"
  openssl req -config root-ca.cnf -new -x509 -days 3650 -sha384 \
    -extensions root_ca_extensions \
    -key private/root-ca.key -passin file:"$passphrase_file" \
    -subj '/O=ApadanaLab/OU=Platform Trust/CN=ApadanaLab Offline Root CA' \
    -out certs/root-ca.crt >/dev/null 2>&1
)

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -out "$tls_dir/tls.key" >/dev/null 2>&1
openssl req -new -sha384 -key "$tls_dir/tls.key" \
  -subj '/O=ApadanaLab/OU=Platform Services/CN=openbao.dev.apadanalab.de' \
  -out "$root_dir/openbao-bootstrap.csr" >/dev/null 2>&1

(
  cd "$root_dir"
  openssl ca -batch -config root-ca.cnf \
    -extensions openbao_bootstrap_server -days 30 -notext -md sha384 \
    -passin file:"$passphrase_file" \
    -in openbao-bootstrap.csr -out "$tls_dir/tls.crt" >/dev/null 2>&1
  openssl ca -batch -config root-ca.cnf -gencrl \
    -passin file:"$passphrase_file" \
    -out "$tls_dir/ca.crl" >/dev/null 2>&1
)

install -m 0600 "$root_dir/certs/root-ca.crt" "$tls_dir/ca.crt"
chmod 0600 "$tls_dir/tls.crt" "$tls_dir/tls.key" "$tls_dir/ca.crl"

OPENBAO_TLS_INPUT_DIR="$tls_dir" \
  ./scripts/validate-openbao-bootstrap-tls.sh >/dev/null

chmod 0644 "$tls_dir/tls.key"
expect_failure \
  "every OpenBao TLS input file must use mode 0600" \
  env OPENBAO_TLS_INPUT_DIR="$tls_dir" \
  ./scripts/validate-openbao-bootstrap-tls.sh

echo "Offline-root policy checks passed."
