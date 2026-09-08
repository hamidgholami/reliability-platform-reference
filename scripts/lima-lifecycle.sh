#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

instance_name="rpr-p1"
template="lima/single-node.yaml"
required_version="2.2.0"
action="${1:-}"

fail()
{
  echo "ERROR: $*" >&2
  exit 1
}

command -v limactl >/dev/null 2>&1 || fail "limactl is required"
actual_version="$(limactl --version | awk '{print $3}')"
[ "$actual_version" = "$required_version" ] ||
  fail "Lima ${required_version} is required; found ${actual_version}"

case "$action" in
  validate)
    limactl validate "$template"
    ;;
  up)
    [ "${PROFILE:-}" = "workstation-validation" ] ||
      fail "set PROFILE=workstation-validation"
    [ "${CONFIRM:-}" = "create-${instance_name}" ] ||
      fail "set CONFIRM=create-${instance_name} to create the disposable VM"
    if limactl list --json | jq -e --arg name "$instance_name" \
      'select(.name == $name)' >/dev/null; then
      fail "Lima instance ${instance_name} already exists"
    fi
    limactl start --name "$instance_name" "$template"
    ;;
  stop)
    limactl stop "$instance_name"
    ;;
  delete)
    [ "${PROFILE:-}" = "workstation-validation" ] ||
      fail "set PROFILE=workstation-validation"
    [ "${CONFIRM:-}" = "delete-${instance_name}" ] ||
      fail "set CONFIRM=delete-${instance_name} to delete the disposable VM"
    limactl delete "$instance_name"
    ;;
  *)
    fail "usage: $0 {validate|up|stop|delete}"
    ;;
esac
