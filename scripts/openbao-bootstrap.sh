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
runtime_dir=${OPENBAO_RUNTIME_DIR:-${RPR_PKI_DIR:+$RPR_PKI_DIR/openbao-runtime}}
intermediate_dir=${RPR_PKI_DIR:+$RPR_PKI_DIR/openbao-intermediate}
gpg_home=
root_token_file=
recovery_passphrase=
entered_input=
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
  recovery_passphrase=
  entered_input=
  if [ -n "$root_token_file" ] && [ -f "$root_token_file" ]; then
    rm -f "$root_token_file"
  fi
  if [ -n "$gpg_home" ] && [ -d "$gpg_home" ]; then
    gpgconf --homedir "$gpg_home" --kill gpg-agent >/dev/null 2>&1 || true
    rm -rf "$gpg_home"
  fi
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

read_secret()
{
  printf '%s' "OpenBao recovery-key passphrase: " >&2
  if [ -t 0 ]; then
    stty -echo
    echo_disabled=1
  fi
  if ! IFS= read -r entered_input; then
    restore_terminal
    fail "could not read the recovery-key passphrase"
  fi
  restore_terminal
  recovery_passphrase=$entered_input
  entered_input=
  [ "${#recovery_passphrase}" -ge 16 ] ||
    fail "the recovery-key passphrase must contain at least 16 characters"
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

incus_exec()
{
  INCUS_CONF="$config_dir" \
    incus exec --project rpr-dev "$remote:bao-01" -- "$@"
}

validate_pki_dns_publication()
{
  for dns_name in dns-01 dns-02; do
    case "$dns_name" in
      dns-01) dns_address=10.20.0.10 ;;
      dns-02) dns_address=10.20.0.11 ;;
    esac
    alias_answer=$(INCUS_CONF="$config_dir" \
      incus exec --project rpr-dev "$remote:$dns_name" -- \
      dig "@$dns_address" openbao.dev.apadanalab.de CNAME \
      +norecurse +short 2>/dev/null | tr -d '\r') ||
      fail "$dns_name could not query the private OpenBao alias"
    address_answer=$(INCUS_CONF="$config_dir" \
      incus exec --project rpr-dev "$remote:$dns_name" -- \
      dig "@$dns_address" bao-01.dev.apadanalab.de A \
      +norecurse +short 2>/dev/null | tr -d '\r') ||
      fail "$dns_name could not query the private OpenBao address"
    [ "$alias_answer" = "bao-01.dev.apadanalab.de." ] ||
      fail "$dns_name returned an unexpected OpenBao alias"
    [ "$address_answer" = "10.20.0.20" ] ||
      fail "$dns_name returned an unexpected OpenBao address"
  done
  echo "Validated the OpenBao PKI endpoint name through both private DNS secondaries."
}

case "$action" in
  kv|pki|leaf) ;;
  *) fail "usage: $0 {kv|pki|leaf}" ;;
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
case "$runtime_dir" in
  /*) ;;
  *) fail "OPENBAO_RUNTIME_DIR must be an absolute protected directory" ;;
esac

repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
for protected_dir in "$recovery_dir" "$runtime_dir" "$intermediate_dir"; do
  case "$protected_dir" in
    "$repo_dir"|"$repo_dir"/*)
      fail "OpenBao protected directories must remain outside the repository"
      ;;
  esac
done

case "$action" in
  kv) expected="bootstrap-openbao-$profile-$remote" ;;
  pki) expected="bootstrap-openbao-pki-$profile-$remote" ;;
  leaf) expected="rotate-openbao-certificate-$profile-$remote" ;;
esac
[ "${CONFIRM:-}" = "$expected" ] || fail "set CONFIRM=$expected"
[ -r "$inventory" ] || fail "OpenBao inventory is missing; run make apply"
[ -r "$recovery_dir/recovery-secret.gpg" ] ||
  fail "the protected recovery secret key is missing"
[ -r "$recovery_dir/initialization.json" ] ||
  fail "the encrypted initialization response is missing"
[ "$(find "$recovery_dir" -prune -type d -perm 0700 -print)" = "$recovery_dir" ] ||
  fail "OPENBAO_RECOVERY_DIR must use mode 0700"
for protected_file in recovery-secret.gpg initialization.json; do
  protected_path="$recovery_dir/$protected_file"
  [ "$(find "$protected_path" -prune -type f -perm 0600 -print)" = "$protected_path" ] ||
    fail "$protected_file must use mode 0600"
done

for tool in gpg gpgconf incus jq openssl; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done
[ -x .venv/bin/ansible-playbook ] || fail "run make setup-python first"

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

status_file=$(mktemp)
if incus_exec env \
  BAO_ADDR=https://10.20.0.20:8200 \
  BAO_CACERT=/opt/openbao/tls/ca.crt \
  BAO_TLS_SERVER_NAME=openbao.dev.apadanalab.de \
  bao status -format=json >"$status_file" 2>/dev/null; then
  status_rc=0
else
  status_rc=$?
fi
case "$status_rc" in
  0|2) ;;
  *) rm -f "$status_file"; fail "could not read the OpenBao seal status" ;;
esac
jq -e '.initialized == true and .sealed == false' "$status_file" >/dev/null || {
  rm -f "$status_file"
  fail "OpenBao must be initialized and unsealed"
}
rm -f "$status_file"

install -d -m 0700 "$runtime_dir"
gpg_home=$(mktemp -d /tmp/rpr-openbao-gpg.XXXXXX)
gpgconf --homedir "$gpg_home" --launch gpg-agent
gpg --homedir "$gpg_home" --batch --quiet \
  --import "$recovery_dir/recovery-secret.gpg"
read_secret

root_token_file=$(mktemp "$runtime_dir/initial-root-token.XXXXXX")
jq -er '.root_token' "$recovery_dir/initialization.json" |
  openssl base64 -d -A |
  gpg_with_passphrase --decrypt >"$root_token_file" ||
  fail "the encrypted initial root token could not be recovered"
chmod 0600 "$root_token_file"
recovery_passphrase=
[ -s "$root_token_file" ] || fail "the recovered initial root token is empty"
root_token_size=$(wc -c <"$root_token_file" | tr -d ' ')
[ "$root_token_size" -ge 16 ] && [ "$root_token_size" -le 4096 ] ||
  fail "the recovered initial root token has an invalid size"

export OPENBAO_ROOT_TOKEN_FILE="$root_token_file"

run_playbook()
{
  INCUS_CONF="$config_dir" \
  ANSIBLE_CONFIG="$PWD/ansible.cfg" \
  ANSIBLE_HOME="$PWD/.cache/ansible" \
  ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
  ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
  .venv/bin/ansible-playbook \
    --diff \
    --inventory "$inventory" \
    "$1"
}

if [ "$action" = "kv" ]; then
  echo "Bootstrapping OpenBao KV and scoped policies: profile=$profile remote=$remote"
  run_playbook ansible/playbooks/bootstrap-openbao.yml
  exit 0
fi

if [ "$action" = "leaf" ]; then
  echo "Rotating the OpenBao listener certificate: profile=$profile remote=$remote"
  run_playbook ansible/playbooks/rotate-openbao-certificate.yml
  exit 0
fi

if [ -e "$intermediate_dir" ] && [ ! -d "$intermediate_dir" ]; then
  fail "the OpenBao intermediate path exists but is not a directory"
fi
install -d -m 0700 "$intermediate_dir"
[ "$(find "$intermediate_dir" -prune -type d -perm 0700 -print)" = "$intermediate_dir" ] ||
  fail "the OpenBao intermediate directory must use mode 0700"

echo "Preparing the OpenBao-held intermediate CSR: profile=$profile remote=$remote"
export OPENBAO_PKI_OUTPUT_DIR="$intermediate_dir"
run_playbook ansible/playbooks/prepare-openbao-pki.yml

issuer_configured=$(jq -r '
  if (.issuer_configured | type) == "boolean" then
    .issuer_configured
  else
    error("issuer_configured must be boolean")
  end
' "$intermediate_dir/state.json") ||
  fail "the PKI preparation result is invalid"
case "$issuer_configured" in
  true|false) ;;
  *) fail "the PKI preparation result is invalid" ;;
esac
if [ "$issuer_configured" = "false" ]; then
  RPR_PKI_DIR="$pki_dir" "$repo_dir/scripts/openbao-pki.sh" sign-intermediate
fi

echo "Importing and validating the signed OpenBao intermediate..."
run_playbook ansible/playbooks/import-openbao-pki.yml
validate_pki_dns_publication
