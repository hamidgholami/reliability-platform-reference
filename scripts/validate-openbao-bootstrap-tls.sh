#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

tls_input_dir=${OPENBAO_TLS_INPUT_DIR:-${RPR_PKI_DIR:+$RPR_PKI_DIR/openbao-bootstrap}}

fail()
{
  echo "Error: $*" >&2
  exit 1
}

file_mode()
{
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

case "$tls_input_dir" in
  /*) ;;
  *) fail "OPENBAO_TLS_INPUT_DIR must be an absolute protected directory" ;;
esac
[ -d "$tls_input_dir" ] || fail "OpenBao TLS input directory is missing"
[ "$(file_mode "$tls_input_dir")" = "700" ] ||
  fail "OpenBao TLS input directory must use mode 0700"

for tls_file in ca.crt ca.crl tls.crt tls.key; do
  [ -r "$tls_input_dir/$tls_file" ] ||
    fail "OpenBao TLS input must contain ca.crt, ca.crl, tls.crt, and tls.key"
  [ "$(file_mode "$tls_input_dir/$tls_file")" = "600" ] ||
    fail "every OpenBao TLS input file must use mode 0600"
done

command -v openssl >/dev/null 2>&1 || fail "openssl is required"

openssl verify -CAfile "$tls_input_dir/ca.crt" \
  "$tls_input_dir/ca.crt" >/dev/null 2>&1 ||
  fail "ca.crt is not a self-signed trust anchor"
openssl x509 -in "$tls_input_dir/ca.crt" -noout -text 2>/dev/null |
  grep -F 'CA:TRUE' >/dev/null || fail "ca.crt is not a CA certificate"
openssl crl -in "$tls_input_dir/ca.crl" -noout -verify \
  -CAfile "$tls_input_dir/ca.crt" >/dev/null 2>&1 ||
  fail "ca.crl is not signed by ca.crt"
openssl verify -crl_check \
  -CAfile "$tls_input_dir/ca.crt" \
  -CRLfile "$tls_input_dir/ca.crl" \
  "$tls_input_dir/tls.crt" >/dev/null 2>&1 ||
  fail "OpenBao listener certificate is untrusted, revoked, or has a stale CRL"
openssl x509 -in "$tls_input_dir/tls.crt" -noout -checkend 604800 \
  >/dev/null 2>&1 || fail "OpenBao listener certificate expires within seven days"
openssl x509 -in "$tls_input_dir/tls.crt" -noout -text 2>/dev/null |
  grep -F 'CA:FALSE' >/dev/null ||
  fail "OpenBao listener certificate must not be a CA"
openssl x509 -in "$tls_input_dir/tls.crt" -noout -purpose 2>/dev/null |
  grep -F 'SSL server : Yes' >/dev/null ||
  fail "OpenBao listener certificate is not valid for TLS server use"

certificate_public_key=$(openssl x509 -in "$tls_input_dir/tls.crt" \
  -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null |
  openssl dgst -sha256 2>/dev/null) ||
  fail "cannot read the OpenBao listener certificate public key"
private_public_key=$(openssl pkey -in "$tls_input_dir/tls.key" -passin pass: \
  -pubout -outform DER 2>/dev/null | openssl dgst -sha256 2>/dev/null) ||
  fail "OpenBao listener key must be readable and unencrypted"
[ "$certificate_public_key" = "$private_public_key" ] ||
  fail "OpenBao listener certificate and key do not match"

openssl x509 -in "$tls_input_dir/tls.crt" -noout \
  -checkhost openbao.dev.apadanalab.de >/dev/null 2>&1 ||
  fail "OpenBao listener certificate is missing a reviewed SAN"
openssl x509 -in "$tls_input_dir/tls.crt" -noout \
  -checkhost bao-01.dev.apadanalab.de >/dev/null 2>&1 ||
  fail "OpenBao listener certificate is missing a reviewed SAN"
openssl x509 -in "$tls_input_dir/tls.crt" -noout \
  -checkip 10.20.0.20 >/dev/null 2>&1 ||
  fail "OpenBao listener certificate is missing a reviewed SAN"

echo "OpenBao bootstrap TLS inputs are valid. Publishable metadata follows."
openssl x509 -in "$tls_input_dir/ca.crt" -noout \
  -subject -serial -dates -fingerprint -sha256
openssl crl -in "$tls_input_dir/ca.crl" -noout \
  -issuer -lastupdate -nextupdate -crlnumber -fingerprint -sha256
openssl x509 -in "$tls_input_dir/tls.crt" -noout \
  -subject -issuer -serial -dates -fingerprint -sha256
