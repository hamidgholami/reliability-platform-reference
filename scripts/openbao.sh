#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

action=${1:-}
profile=${PROFILE:-}
config_dir=${INCUS_CONFIG_DIR:-}
remote=${INCUS_REMOTE:-}
inventory=${OPENBAO_INVENTORY:-"$PWD/.cache/incus-substrate/openbao-hosts.json"}
tls_input_dir=${OPENBAO_TLS_INPUT_DIR:-}

fail()
{
  echo "Error: $*" >&2
  exit 1
}

case "$action" in
  configure|status|validate) ;;
  *) fail "usage: $0 {configure|status|validate}" ;;
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

if [ "$action" = "configure" ]; then
  expected="configure-openbao-$profile-$remote"
  [ "${CONFIRM:-}" = "$expected" ] ||
    fail "set CONFIRM=$expected to configure the OpenBao service"
  OPENBAO_TLS_INPUT_DIR="$tls_input_dir" \
    ./scripts/validate-openbao-bootstrap-tls.sh >/dev/null
fi

[ -r "$inventory" ] || fail "OpenBao inventory is missing; run make apply"
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

case "$action" in
  configure)
    playbook=ansible/playbooks/configure-openbao.yml
    echo "Configuring OpenBao: profile=$profile remote=$remote inventory=$inventory"
    ;;
  status)
    playbook=ansible/playbooks/openbao-status.yml
    echo "Reading OpenBao status: profile=$profile remote=$remote inventory=$inventory"
    ;;
  validate)
    playbook=ansible/playbooks/validate-openbao.yml
    echo "Validating OpenBao: profile=$profile remote=$remote inventory=$inventory"
    ;;
esac

export OPENBAO_TLS_INPUT_DIR="$tls_input_dir"
INCUS_CONF="$config_dir" \
ANSIBLE_CONFIG="$PWD/ansible.cfg" \
ANSIBLE_HOME="$PWD/.cache/ansible" \
ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
.venv/bin/ansible-playbook \
  --diff \
  --inventory "$inventory" \
  "$playbook"
