#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu
umask 077

profile=${PROFILE:-}
config_dir=${INCUS_CONFIG_DIR:-}
remote=${INCUS_REMOTE:-}
inventory=${OPENBAO_INVENTORY:-"$PWD/.cache/incus-substrate/openbao-hosts.json"}

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

expected="accept-ssh-certificates-$profile-$remote"
[ "${CONFIRM:-}" = "$expected" ] || fail "set CONFIRM=$expected"
[ -r "$inventory" ] || fail "generated inventory is missing; run make validate"
[ -x .venv/bin/ansible-playbook ] || fail "run make setup-python first"
command -v jq >/dev/null 2>&1 || fail "jq is required"

jq -e --arg profile "$profile" --arg remote "$remote" '
  .all.children.machine_auth_client as $client
  | .all.children.ssh_test_target as $target
  | $client.vars.rpr_deployment_profile == $profile
  and $target.vars.rpr_deployment_profile == $profile
  and $client.vars.ansible_incus_remote == $remote
  and $target.vars.ansible_incus_remote == $remote
  and $client.vars.ansible_incus_project == "rpr-dev"
  and $target.vars.ansible_incus_project == "rpr-dev"
  and ($client.hosts | keys) == ["smoke-01"]
  and ($target.hosts | keys) == ["ssh-test-01"]
  and $target.vars.ssh_test_private_address == "10.20.0.221"
  and $target.vars.ssh_test_private_dns_name == "ssh-test-01.dev.apadanalab.de"
' "$inventory" >/dev/null || fail "SSH certificate inventory violates the reviewed boundary"

echo "Accepting the Ed25519 SSH certificate path: profile=$profile remote=$remote"
INCUS_CONF="$config_dir" \
ANSIBLE_CONFIG="$PWD/ansible.cfg" \
ANSIBLE_HOME="$PWD/.cache/ansible" \
ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
.venv/bin/ansible-playbook \
  --diff \
  --inventory "$inventory" \
  ansible/playbooks/accept-ssh-certificates.yml
