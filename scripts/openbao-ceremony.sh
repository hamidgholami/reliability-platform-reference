#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu
umask 077

action=${1:-}
profile=${PROFILE:-}
config_dir=${INCUS_CONFIG_DIR:-}
remote=${INCUS_REMOTE:-}
inventory=${OPENBAO_INVENTORY:-"$PWD/.cache/incus-substrate/openbao-hosts.json"}
pki_dir=${RPR_PKI_DIR:-}
recovery_dir=${OPENBAO_RECOVERY_DIR:-${RPR_PKI_DIR:+$RPR_PKI_DIR/openbao-recovery}}
stage_dir=
gpg_home=
status_file=
recovery_passphrase=
entered_input=
echo_disabled=0
remote_public_key_installed=0
initialization_completed=0
remote_public_key=/run/rpr-openbao-recovery-public.gpg

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

incus_exec()
{
  INCUS_CONF="$config_dir" \
    incus exec --project rpr-dev "$remote:bao-01" -- "$@"
}

bao_cli()
{
  incus_exec env \
    BAO_ADDR=https://10.20.0.20:8200 \
    BAO_CACERT=/opt/openbao/tls/ca.crt \
    BAO_TLS_SERVER_NAME=openbao.dev.apadanalab.de \
    bao "$@"
}

cleanup()
{
  restore_terminal
  recovery_passphrase=
  entered_input=
  if [ "$remote_public_key_installed" -eq 1 ]; then
    incus_exec rm -f "$remote_public_key" >/dev/null 2>&1 || true
  fi
  if [ -n "$stage_dir" ] && [ -d "$stage_dir" ]; then
    if [ "$initialization_completed" -eq 1 ]; then
      echo "Recovery material retained after post-initialization failure: $stage_dir" >&2
    else
      rm -rf "$stage_dir"
    fi
  fi
  if [ -n "$gpg_home" ] && [ -d "$gpg_home" ]; then
    gpgconf --homedir "$gpg_home" --kill gpg-agent >/dev/null 2>&1 || true
    rm -rf "$gpg_home"
  fi
  if [ -n "$status_file" ] && [ -f "$status_file" ]; then
    rm -f "$status_file"
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
  if ! IFS= read -r entered_input; then
    restore_terminal
    fail "could not read the recovery-key passphrase"
  fi
  restore_terminal
}

read_recovery_passphrase()
{
  confirm=${1:-false}
  read_secret "OpenBao recovery-key passphrase: "
  recovery_passphrase=$entered_input
  entered_input=
  [ "${#recovery_passphrase}" -ge 16 ] ||
    fail "the recovery-key passphrase must contain at least 16 characters"

  if [ "$confirm" = "true" ]; then
    read_secret "Confirm OpenBao recovery-key passphrase: "
    [ "$recovery_passphrase" = "$entered_input" ] ||
      fail "the recovery-key passphrases do not match"
    entered_input=
  fi
}

gpg_with_passphrase()
{
  gpg \
    --homedir "$gpg_home" \
    --batch \
    --quiet \
    --pinentry-mode loopback \
    --passphrase-fd 3 \
    "$@" 3<<EOF
$recovery_passphrase
EOF
}

read_status()
{
  status_file=$(mktemp)
  if bao_cli status -format=json >"$status_file" 2>/dev/null; then
    status_rc=0
  else
    status_rc=$?
  fi
  case "$status_rc" in
    0|2) ;;
    *) fail "could not read the OpenBao seal status" ;;
  esac
  jq -e '
    (.initialized | type) == "boolean"
    and (.sealed | type) == "boolean"
  ' "$status_file" >/dev/null || fail "OpenBao returned an invalid seal status"
}

case "$action" in
  initialize|unseal) ;;
  *) fail "usage: $0 {initialize|unseal}" ;;
esac
case "$profile" in
  workstation-validation|single-node-reference) ;;
  *) fail "set PROFILE to workstation-validation or single-node-reference" ;;
esac
case "$config_dir" in
  /*) ;;
  *) fail "INCUS_CONFIG_DIR must be an absolute path" ;;
esac
[ -n "$remote" ] || fail "set INCUS_REMOTE to the pre-enrolled remote name"
case "$remote" in
  *[!A-Za-z0-9_.-]*|'') fail "INCUS_REMOTE contains unsupported characters" ;;
esac
case "$pki_dir" in
  /*) ;;
  *) fail "RPR_PKI_DIR must be an absolute protected directory" ;;
esac
case "$recovery_dir" in
  /*) ;;
  *) fail "OPENBAO_RECOVERY_DIR must be an absolute protected directory" ;;
esac

repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
case "$recovery_dir" in
  "$repo_dir"|"$repo_dir"/*)
    fail "OPENBAO_RECOVERY_DIR must remain outside the repository"
    ;;
esac

expected="$action-openbao-$profile-$remote"
[ "${CONFIRM:-}" = "$expected" ] || fail "set CONFIRM=$expected"
[ -d "$pki_dir" ] || fail "RPR_PKI_DIR does not exist; create the operator PKI first"
[ -r "$inventory" ] || fail "OpenBao inventory is missing; run make apply"

for tool in gpg gpgconf incus jq openssl; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

jq -e \
  --arg profile "$profile" \
  --arg remote "$remote" '
    .all.children.openbao_service as $bao
    | $bao.vars.rpr_deployment_profile == $profile
    and $bao.vars.ansible_incus_remote == $remote
    and $bao.vars.ansible_incus_project == "rpr-dev"
    and $bao.vars.openbao_platform_cidr == "10.20.0.0/24"
    and $bao.vars.openbao_api_address == "10.20.0.20"
    and $bao.vars.openbao_api_port == 8200
    and $bao.vars.openbao_api_dns_name == "openbao.dev.apadanalab.de"
    and ($bao.hosts | keys) == ["bao-01"]
    and $bao.hosts["bao-01"].ansible_host == "bao-01"
  ' "$inventory" >/dev/null || fail "OpenBao inventory violates the reviewed boundary"

read_status
initialized=$(jq -r '.initialized' "$status_file")
sealed=$(jq -r '.sealed' "$status_file")
rm -f "$status_file"
status_file=

if [ "$action" = "initialize" ]; then
  [ "$initialized" = "false" ] || fail "OpenBao is already initialized"
  [ "$sealed" = "true" ] || fail "an uninitialized OpenBao service must be sealed"
  [ ! -e "$recovery_dir" ] && [ ! -L "$recovery_dir" ] ||
    fail "refusing to overwrite existing OpenBao recovery material"

  read_recovery_passphrase true
  recovery_parent=$(dirname "$recovery_dir")
  mkdir -p "$recovery_parent"
  stage_dir=$(mktemp -d "${recovery_dir}.create.XXXXXX")
  gpg_home=$(mktemp -d /tmp/rpr-openbao-gpg.XXXXXX)
  gpgconf --homedir "$gpg_home" --launch gpg-agent
  recovery_dir_saved=$recovery_dir
  recovery_dir=$stage_dir

  recovery_uid="RPR OpenBao Recovery ($profile $remote)"
  gpg_with_passphrase \
    --quick-generate-key "$recovery_uid" rsa3072 encr 0
  recovery_fingerprint=$(gpg \
    --homedir "$gpg_home" \
    --batch --with-colons --list-secret-keys "$recovery_uid" |
    awk -F: '$1 == "fpr" { print $10; exit }')
  [ -n "$recovery_fingerprint" ] || fail "could not identify the recovery key"
  gpg \
    --homedir "$gpg_home" \
    --batch --export "$recovery_fingerprint" \
    >"$recovery_dir/recovery-public.gpg"
  gpg_with_passphrase --export-secret-keys "$recovery_fingerprint" \
    >"$recovery_dir/recovery-secret.gpg"
  chmod 0600 \
    "$recovery_dir/recovery-public.gpg" \
    "$recovery_dir/recovery-secret.gpg"

  printf 'openbao-recovery-key-check\n' |
    gpg \
      --homedir "$gpg_home" \
      --batch --quiet --trust-model always \
      --recipient "$recovery_fingerprint" --encrypt \
      >"$recovery_dir/key-check.gpg"
  gpg_with_passphrase --decrypt "$recovery_dir/key-check.gpg" |
    grep -Fx 'openbao-recovery-key-check' >/dev/null ||
    fail "the generated recovery key did not pass encryption validation"
  rm -f "$recovery_dir/key-check.gpg"

  incus_exec sh -c \
    'umask 077; cat > /run/rpr-openbao-recovery-public.gpg' \
    <"$recovery_dir/recovery-public.gpg"
  remote_public_key_installed=1

  echo "Initializing OpenBao with one PGP-encrypted recovery share..."
  if ! bao_cli operator init \
    -format=json \
    -key-shares=1 \
    -key-threshold=1 \
    -pgp-keys="$remote_public_key" \
    -root-token-pgp-key="$remote_public_key" \
    >"$recovery_dir/initialization.json"; then
    fail "OpenBao initialization failed"
  fi
  initialization_completed=1
  chmod 0600 "$recovery_dir/initialization.json"

  jq -e '
    (.unseal_keys_b64 | length) == 1
    and (.unseal_keys_b64[0] | type) == "string"
    and (.unseal_keys_b64[0] | length) > 0
    and (.root_token | type) == "string"
    and (.root_token | length) > 0
  ' "$recovery_dir/initialization.json" >/dev/null ||
    fail "OpenBao did not return the expected encrypted recovery bundle"

  jq -er '.unseal_keys_b64[0]' "$recovery_dir/initialization.json" |
    openssl base64 -d -A |
    gpg_with_passphrase --decrypt |
    awk 'length($0) >= 16 { valid = 1 } END { exit !valid }' ||
    fail "the encrypted unseal share could not be recovered"
  jq -er '.root_token' "$recovery_dir/initialization.json" |
    openssl base64 -d -A |
    gpg_with_passphrase --decrypt |
    awk 'length($0) >= 16 { valid = 1 } END { exit !valid }' ||
    fail "the encrypted initial root token could not be recovered"

  incus_exec rm -f "$remote_public_key"
  remote_public_key_installed=0
  recovery_passphrase=
  recovery_dir=$recovery_dir_saved
  mv "$stage_dir" "$recovery_dir"
  stage_dir=
  initialization_completed=0

  read_status
  jq -e '.initialized == true and .sealed == true' "$status_file" >/dev/null ||
    fail "OpenBao initialized but did not reach the expected sealed state"

  echo "OpenBao initialized and remains sealed."
  echo "Encrypted recovery material was created under OPENBAO_RECOVERY_DIR."
  echo "Back up that complete directory before relying on the service."
  exit 0
fi

[ "$initialized" = "true" ] || fail "OpenBao is not initialized"
if [ "$sealed" = "false" ]; then
  echo "OpenBao is already unsealed; no recovery material was read."
  exit 0
fi
[ -r "$recovery_dir/recovery-secret.gpg" ] ||
  fail "the protected recovery secret key is missing"
[ -r "$recovery_dir/initialization.json" ] || fail "the encrypted recovery bundle is missing"
[ "$(find "$recovery_dir" -prune -type d -perm 0700 -print)" = "$recovery_dir" ] ||
  fail "OPENBAO_RECOVERY_DIR must use mode 0700"
for protected_file in recovery-secret.gpg initialization.json; do
  protected_path="$recovery_dir/$protected_file"
  [ "$(find "$protected_path" -prune -type f -perm 0600 -print)" = "$protected_path" ] ||
    fail "$protected_file must use mode 0600"
done

gpg_home=$(mktemp -d /tmp/rpr-openbao-gpg.XXXXXX)
gpgconf --homedir "$gpg_home" --launch gpg-agent
gpg --homedir "$gpg_home" --batch --quiet \
  --import "$recovery_dir/recovery-secret.gpg"
read_recovery_passphrase false
echo "Presenting the decrypted recovery share through standard input..."
status_file=$(mktemp)
jq -er '.unseal_keys_b64[0]' "$recovery_dir/initialization.json" |
  openssl base64 -d -A |
  gpg_with_passphrase --decrypt |
  bao_cli write -format=json sys/unseal key=- >"$status_file" ||
  fail "OpenBao unseal failed"
recovery_passphrase=

jq -e '.sealed == false' "$status_file" >/dev/null ||
  fail "OpenBao did not report an unsealed state"
echo "OpenBao is unsealed. No recovery share was written to disk or output."
