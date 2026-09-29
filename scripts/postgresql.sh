#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu
umask 077

profile=${PROFILE:-}
config_dir=${INCUS_CONFIG_DIR:-}
remote=${INCUS_REMOTE:-}
inventory=${OPENBAO_INVENTORY:-"$PWD/.cache/incus-substrate/openbao-hosts.json"}
substrate_inventory="$PWD/.cache/incus-substrate/inventory.json"

fail()
{
  echo "Error: $*" >&2
  exit 1
}

case "$profile" in
  workstation-validation|single-node-reference) ;;
  *) fail "set PROFILE to workstation-validation or single-node-reference" ;;
esac
case "$config_dir" in
  /*) ;;
  *) fail "INCUS_CONFIG_DIR must be an absolute path" ;;
esac
case "$remote" in
  *[!A-Za-z0-9_.-]*|'') fail "set INCUS_REMOTE to the pre-enrolled remote name" ;;
esac

expected="configure-postgresql-$profile-$remote"
[ "${CONFIRM:-}" = "$expected" ] || fail "set CONFIRM=$expected"
[ -r "$inventory" ] || fail "generated inventory is missing; run make validate"
[ -r "$substrate_inventory" ] || fail "substrate inventory is missing; run make validate"
[ -x .venv/bin/ansible-playbook ] || fail "run make setup-python first"
command -v jq >/dev/null 2>&1 || fail "jq is required"

client_ipv4=$(jq -er '.instances[] | select(.name == "smoke-01" and .status == "Running") | .ipv4_address' "$substrate_inventory") || fail "running smoke-01 is missing from substrate inventory"

jq -e --arg profile "$profile" --arg remote "$remote" --arg client_ipv4 "$client_ipv4" '
  .all.children.postgresql_service as $pg
  | .all.children.openbao_service as $bao
  | .all.children.machine_auth_client as $client
  | $pg.vars.rpr_deployment_profile == $profile
  and $pg.vars.ansible_incus_remote == $remote
  and $pg.vars.ansible_incus_project == "rpr-dev"
  and ($pg.hosts | keys) == ["pg-01"]
  and $pg.hosts["pg-01"].ansible_host == "pg-01"
  and $pg.vars.postgresql_private_address == "10.20.0.21"
  and $pg.vars.postgresql_private_dns_name == "pg-01.dev.apadanalab.de"
  and $pg.vars.postgresql_listen_port == 5432
  and $pg.vars.postgresql_openbao_address == $bao.vars.openbao_api_address
  and $pg.vars.postgresql_client_address == $client_ipv4
' "$inventory" >/dev/null || fail "PostgreSQL inventory violates the reviewed boundary"

echo "Configuring local PostgreSQL 17: profile=$profile remote=$remote target=pg-01"
INCUS_CONF="$config_dir" \
ANSIBLE_CONFIG="$PWD/ansible.cfg" \
ANSIBLE_HOME="$PWD/.cache/ansible" \
ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
.venv/bin/ansible-playbook \
  --diff \
  --inventory "$inventory" \
  ansible/playbooks/configure-postgresql.yml
