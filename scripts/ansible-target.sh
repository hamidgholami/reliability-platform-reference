#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

action=${1:-}
profile=${PROFILE:-}
inventory=${INVENTORY:-}
target_host=${TARGET_HOST:-}
public_key_file=${OPERATOR_PUBLIC_KEY_FILE:-}
ssh_identity_file=${OPERATOR_SSH_IDENTITY_FILE:-}
profile_vars_file=ansible/inventories/single-node-reference/group_vars/incus_hosts.yml

fail() {
  echo "Error: $*" >&2
  exit 1
}

case "$action" in
  preflight|baseline-check|baseline|validate-baseline|preflight-incus|bootstrap-incus|validate-incus|private-dns-primary-check|private-dns-primary|validate-private-dns-primary) ;;
  *) fail "unsupported Ansible target action: $action" ;;
esac

case "$profile" in
  single-node-reference|workstation-validation) ;;
  *) fail "set PROFILE to single-node-reference or workstation-validation" ;;
esac

[ -n "$inventory" ] || fail "set INVENTORY to an explicit, ignored inventory file"
[ -f "$inventory" ] || fail "inventory file does not exist: $inventory"
[ -n "$target_host" ] || fail "set TARGET_HOST to one inventory hostname"

case "$target_host" in
  *[!A-Za-z0-9_.-]*) fail "TARGET_HOST contains unsupported characters" ;;
esac

[ -n "$public_key_file" ] || fail "set OPERATOR_PUBLIC_KEY_FILE to a public key"
[ -r "$public_key_file" ] || fail "public key is not readable: $public_key_file"
[ -r "$profile_vars_file" ] || fail "profile variables are not readable: $profile_vars_file"
[ -z "$ssh_identity_file" ] || [ -r "$ssh_identity_file" ] ||
  fail "SSH identity file is not readable: $ssh_identity_file"
[ -x .venv/bin/ansible-playbook ] || fail "run 'make setup-python' first"

extra_vars="debian_prepare_operator_public_key_file=$public_key_file rpr_deployment_profile=$profile"

run_playbook() {
  set -- --diff "$@"
  if [ -n "$ssh_identity_file" ]; then
    set -- --private-key "$ssh_identity_file" "$@"
  fi
  ANSIBLE_CONFIG="$PWD/ansible.cfg" \
  ANSIBLE_HOME="$PWD/.cache/ansible" \
  ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
  ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
  .venv/bin/ansible-playbook \
    --inventory "$inventory" \
    --limit "$target_host" \
    --extra-vars "@$profile_vars_file" \
    --extra-vars "$extra_vars" \
    "$@"
}

case "$action" in
  preflight)
    echo "Read-only preflight: profile=$profile target=$target_host inventory=$inventory"
    run_playbook ansible/playbooks/preflight.yml
    ;;
  baseline-check)
    echo "Check-mode preview: profile=$profile target=$target_host inventory=$inventory"
    run_playbook --check ansible/playbooks/baseline.yml
    ;;
  baseline)
    expected="baseline-$profile-$target_host"
    [ "${CONFIRM:-}" = "$expected" ] || fail "set CONFIRM=$expected to mutate this target"
    echo "Mutating baseline: profile=$profile target=$target_host inventory=$inventory"
    run_playbook ansible/playbooks/baseline.yml
    ;;
  validate-baseline)
    echo "Read-only validation: profile=$profile target=$target_host inventory=$inventory"
    run_playbook ansible/playbooks/validate-baseline.yml
    ;;
  preflight-incus)
    echo "Read-only Incus preflight: profile=$profile target=$target_host inventory=$inventory"
    run_playbook ansible/playbooks/preflight-incus.yml
    ;;
  bootstrap-incus)
    expected="bootstrap-incus-$profile-$target_host"
    [ "${CONFIRM:-}" = "$expected" ] || fail "set CONFIRM=$expected to mutate this target"
    echo "Mutating Incus host: profile=$profile target=$target_host inventory=$inventory"
    run_playbook ansible/playbooks/bootstrap-incus.yml
    ;;
  validate-incus)
    echo "Read-only Incus validation: profile=$profile target=$target_host inventory=$inventory"
    run_playbook ansible/playbooks/validate-incus.yml
    ;;
  private-dns-primary-check)
    echo "Check-mode private DNS primary preview: profile=$profile target=$target_host inventory=$inventory"
    run_playbook --check ansible/playbooks/configure-incus-dns-primary.yml
    ;;
  private-dns-primary)
    expected="private-dns-primary-$profile-$target_host"
    [ "${CONFIRM:-}" = "$expected" ] ||
      fail "set CONFIRM=$expected to enable the private Incus DNS listener"
    echo "Configuring private DNS primary: profile=$profile target=$target_host inventory=$inventory"
    run_playbook ansible/playbooks/configure-incus-dns-primary.yml
    ;;
  validate-private-dns-primary)
    echo "Read-only private DNS primary validation: profile=$profile target=$target_host inventory=$inventory"
    run_playbook ansible/playbooks/validate-incus-dns-primary.yml
    ;;
esac
