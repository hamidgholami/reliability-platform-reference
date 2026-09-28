#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu
umask 077

action=${1:-}
pki_dir=${RPR_PKI_DIR:-}
stage_dir=
root_passphrase=
echo_disabled=0

fail()
{
  echo "Error: $*" >&2
  exit 1
}

restore_terminal()
{
  if [ "$echo_disabled" -eq 1 ]; then
    stty echo >/dev/null 2>&1 || true
    printf '\n' >&2
    echo_disabled=0
  fi
}

cleanup()
{
  restore_terminal
  root_passphrase=
  if [ -n "$stage_dir" ] && [ -d "$stage_dir" ]; then
    rm -rf "$stage_dir"
  fi
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

read_secret()
{
  prompt=$1
  printf '%s' "$prompt" >&2
  if [ -t 0 ]; then
    stty -echo
    echo_disabled=1
  fi
  if ! IFS= read -r secret_value; then
    restore_terminal
    fail "could not read the root CA passphrase"
  fi
  restore_terminal
}

read_root_passphrase()
{
  confirm=${1:-false}
  read_secret "Root CA passphrase: "
  root_passphrase=$secret_value
  secret_value=
  [ "${#root_passphrase}" -ge 16 ] ||
    fail "the root CA passphrase must contain at least 16 characters"

  if [ "$confirm" = "true" ]; then
    read_secret "Confirm root CA passphrase: "
    [ "$root_passphrase" = "$secret_value" ] ||
      fail "the root CA passphrases do not match"
    secret_value=
  fi
}

run_with_root_passphrase()
{
  printf '%s\n' "$root_passphrase" | "$@"
}

case "$action" in
  create|renew) ;;
  *) fail "usage: $0 {create|renew}" ;;
esac
case "$pki_dir" in
  /*) ;;
  *) fail "RPR_PKI_DIR must be an absolute path outside the repository" ;;
esac

repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
case "$pki_dir" in
  "$repo_dir"|"$repo_dir"/*)
    fail "RPR_PKI_DIR must remain outside the repository"
    ;;
esac

command -v openssl >/dev/null 2>&1 || fail "openssl is required"

root_dir="$pki_dir/root-ca"
runtime_dir="$pki_dir/openbao-bootstrap"
policy_file="$repo_dir/pki/offline-root/root-ca.cnf"

if [ "$action" = "create" ]; then
  if [ -e "$pki_dir" ] || [ -L "$pki_dir" ]; then
    fail "RPR_PKI_DIR already exists; refusing to overwrite root CA state"
  fi

  pki_parent=$(dirname "$pki_dir")
  mkdir -p "$pki_parent"
  stage_dir=$(mktemp -d "${pki_dir}.create.XXXXXX")
  root_dir="$stage_dir/root-ca"
  runtime_dir="$stage_dir/openbao-bootstrap"

  install -d -m 0700 \
    "$root_dir/certs" \
    "$root_dir/crl" \
    "$root_dir/newcerts" \
    "$root_dir/private" \
    "$root_dir/requests" \
    "$runtime_dir"
  install -m 0600 "$policy_file" "$root_dir/root-ca.cnf"
  : >"$root_dir/index.txt"
  printf '1000\n' >"$root_dir/serial"
  printf '1000\n' >"$root_dir/crlnumber"
  chmod 0600 "$root_dir/index.txt" "$root_dir/serial" "$root_dir/crlnumber"

  read_root_passphrase true

  echo "Creating the encrypted ten-year root CA..."
  run_with_root_passphrase openssl genpkey \
    -algorithm RSA \
    -pkeyopt rsa_keygen_bits:4096 \
    -aes-256-cbc \
    -pass stdin \
    -out "$root_dir/private/root-ca.key"
  chmod 0600 "$root_dir/private/root-ca.key"

  (
    cd "$root_dir"
    printf '%s\n' "$root_passphrase" | openssl req \
      -config root-ca.cnf \
      -new -x509 \
      -days 3650 \
      -sha384 \
      -extensions root_ca_extensions \
      -key private/root-ca.key \
      -passin stdin \
      -subj '/O=ApadanaLab/OU=Platform Trust/CN=ApadanaLab Offline Root CA' \
      -out certs/root-ca.crt
  )

  echo "Issuing the one-year OpenBao listener certificate..."
  openssl genpkey \
    -algorithm RSA \
    -pkeyopt rsa_keygen_bits:3072 \
    -out "$runtime_dir/tls.key"
  openssl req \
    -new \
    -sha384 \
    -key "$runtime_dir/tls.key" \
    -subj '/O=ApadanaLab/OU=Platform Services/CN=openbao.dev.apadanalab.de' \
    -out "$root_dir/requests/openbao-bootstrap.csr"

  (
    cd "$root_dir"
    printf '%s\n' "$root_passphrase" | openssl ca \
      -batch \
      -config root-ca.cnf \
      -extensions openbao_bootstrap_server \
      -days 365 \
      -notext \
      -md sha384 \
      -passin stdin \
      -in requests/openbao-bootstrap.csr \
      -out "$runtime_dir/tls.crt"
    printf '%s\n' "$root_passphrase" | openssl ca \
      -batch \
      -config root-ca.cnf \
      -gencrl \
      -crldays 365 \
      -passin stdin \
      -out crl/root-ca.crl
  )

  install -m 0600 "$root_dir/certs/root-ca.crt" "$runtime_dir/ca.crt"
  install -m 0600 "$root_dir/crl/root-ca.crl" "$runtime_dir/ca.crl"
  chmod 0600 "$runtime_dir/tls.key" "$runtime_dir/tls.crt"

  OPENBAO_TLS_INPUT_DIR="$runtime_dir" \
    "$repo_dir/scripts/validate-openbao-bootstrap-tls.sh"

  root_passphrase=
  mv "$stage_dir" "$pki_dir"
  stage_dir=

  echo "Created protected OpenBao PKI material under RPR_PKI_DIR."
  echo "Back up the complete root-ca directory to encrypted offline storage."
  exit 0
fi

[ -d "$pki_dir" ] || fail "RPR_PKI_DIR does not exist; create it first"
[ -d "$root_dir" ] || fail "the root CA directory is missing"
[ -d "$runtime_dir" ] || fail "the current OpenBao TLS directory is missing"
[ -r "$root_dir/private/root-ca.key" ] || fail "the encrypted root CA key is missing"
[ -r "$root_dir/certs/root-ca.crt" ] || fail "the root CA certificate is missing"
[ -r "$root_dir/root-ca.cnf" ] || fail "the root CA policy is missing"
cmp -s "$policy_file" "$root_dir/root-ca.cnf" ||
  fail "the stored root CA policy differs from the reviewed repository policy"

read_root_passphrase false
run_with_root_passphrase openssl pkey \
  -in "$root_dir/private/root-ca.key" \
  -passin stdin \
  -check -noout

stage_dir=$(mktemp -d "$pki_dir/.renew.XXXXXX")
new_runtime_dir="$stage_dir/openbao-bootstrap"
install -d -m 0700 "$new_runtime_dir"

echo "Issuing a renewed one-year OpenBao listener certificate..."
openssl genpkey \
  -algorithm RSA \
  -pkeyopt rsa_keygen_bits:3072 \
  -out "$new_runtime_dir/tls.key"
openssl req \
  -new \
  -sha384 \
  -key "$new_runtime_dir/tls.key" \
  -subj '/O=ApadanaLab/OU=Platform Services/CN=openbao.dev.apadanalab.de' \
  -out "$stage_dir/openbao-bootstrap.csr"

(
  cd "$root_dir"
  printf '%s\n' "$root_passphrase" | openssl ca \
    -batch \
    -config root-ca.cnf \
    -extensions openbao_bootstrap_server \
    -days 365 \
    -notext \
    -md sha384 \
    -passin stdin \
    -in "$stage_dir/openbao-bootstrap.csr" \
    -out "$new_runtime_dir/tls.crt"
  printf '%s\n' "$root_passphrase" | openssl ca \
    -batch \
    -config root-ca.cnf \
    -gencrl \
    -crldays 365 \
    -passin stdin \
    -out "$new_runtime_dir/ca.crl"
)

install -m 0600 "$root_dir/certs/root-ca.crt" "$new_runtime_dir/ca.crt"
chmod 0600 \
  "$new_runtime_dir/ca.crt" \
  "$new_runtime_dir/ca.crl" \
  "$new_runtime_dir/tls.crt" \
  "$new_runtime_dir/tls.key"

OPENBAO_TLS_INPUT_DIR="$new_runtime_dir" \
  "$repo_dir/scripts/validate-openbao-bootstrap-tls.sh"

archive_dir="$pki_dir/archive"
install -d -m 0700 "$archive_dir"
archive_name="openbao-bootstrap-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mv "$runtime_dir" "$archive_dir/$archive_name"
if ! mv "$new_runtime_dir" "$runtime_dir"; then
  mv "$archive_dir/$archive_name" "$runtime_dir"
  fail "could not install the renewed listener material"
fi
install -m 0600 "$runtime_dir/ca.crl" "$root_dir/crl/root-ca.crl"

root_passphrase=
echo "Renewed the OpenBao listener certificate and archived the previous input."
echo "Back up the updated root-ca directory before relying on the renewal."
