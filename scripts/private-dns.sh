#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

action=${1:-}
profile=${PROFILE:-}
config_dir=${INCUS_CONFIG_DIR:-}
remote=${INCUS_REMOTE:-}
inventory=${PRIVATE_DNS_INVENTORY:-"$PWD/.cache/incus-substrate/private-dns-hosts.json"}
secrets_file=${PRIVATE_DNS_SECRETS_FILE:-"$PWD/.cache/private-dns/tsig.auto.tfvars.json"}

fail()
{
  echo "Error: $*" >&2
  exit 1
}

case "$action" in
  configure|validate) ;;
  *) fail "usage: $0 {configure|validate}" ;;
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
  expected="configure-private-dns-$profile-$remote"
  [ "${CONFIRM:-}" = "$expected" ] ||
    fail "set CONFIRM=$expected to configure both BIND secondaries"
fi
[ -r "$inventory" ] || fail "private DNS inventory is missing; run make apply"
[ -r "$secrets_file" ] || fail "private DNS secrets are missing; run make private-dns-secrets"
[ -x .venv/bin/ansible-playbook ] || fail "run make setup-python first"

secret_mode="$(stat -f '%Lp' "$secrets_file" 2>/dev/null || stat -c '%a' "$secrets_file")"
[ "$secret_mode" = "600" ] || fail "private DNS secrets must use mode 0600"

jq -e \
  --arg profile "$profile" \
  --arg remote "$remote" '
    .all.children.dns_secondaries as $dns
    | $dns.vars.rpr_deployment_profile == $profile
    and $dns.vars.ansible_incus_remote == $remote
    and $dns.vars.ansible_incus_project == "rpr-dev"
    and ($dns.hosts | keys) == ["dns-01", "dns-02"]
    and $dns.hosts["dns-01"].bind_secondary_listen_address == "10.20.0.10"
    and $dns.hosts["dns-02"].bind_secondary_listen_address == "10.20.0.11"
  ' "$inventory" >/dev/null || fail "private DNS inventory violates the reviewed boundary"

jq -e '
  .private_dns_tsig_secrets as $secrets
  | ($secrets | keys) == ["dns-01", "dns-02"]
  and (["dns-01", "dns-02"] | all(
    ($secrets[.].forward | length) >= 32
    and ($secrets[.].reverse | length) >= 32
  ))
' "$secrets_file" >/dev/null || fail "private DNS secret input is invalid"

if [ "$action" = "configure" ]; then
  playbook=ansible/playbooks/configure-private-dns.yml
  echo "Configuring private DNS secondaries: profile=$profile remote=$remote inventory=$inventory"
else
  playbook=ansible/playbooks/validate-private-dns.yml
  echo "Validating private DNS secondaries: profile=$profile remote=$remote inventory=$inventory"
fi

INCUS_CONF="$config_dir" \
ANSIBLE_CONFIG="$PWD/ansible.cfg" \
ANSIBLE_HOME="$PWD/.cache/ansible" \
ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
.venv/bin/ansible-playbook \
  --diff \
  --inventory "$inventory" \
  --extra-vars "@$secrets_file" \
  "$playbook"
