#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

instance_name="rpr-p1"
inventory_host="incus-lima-01"
template="lima/single-node.yaml"
required_version="2.2.0"
cache_dir=${RPR_LIMA_CACHE_DIR:-"$PWD/.cache/lima"}
inventory_file="$cache_dir/hosts.json"
action="${1:-}"

fail()
{
  echo "ERROR: $*" >&2
  exit 1
}

require_tool()
{
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

require_profile()
{
  [ "${PROFILE:-}" = "workstation-validation" ] ||
    fail "set PROFILE=workstation-validation"
}

require_lima()
{
  require_tool limactl
  actual_version="$(limactl --version | awk '{print $3}')"
  [ "$actual_version" = "$required_version" ] ||
    fail "Lima ${required_version} is required; found ${actual_version}"
}

instance_exists()
{
  listed_name="$(limactl list --format '{{.Name}}' "$instance_name" 2>/dev/null)" ||
    return 1
  [ "$listed_name" = "$instance_name" ]
}

generate_inventory()
{
  require_tool jq
  require_tool ssh

  instance_status="$(limactl list --format '{{.Status}}' "$instance_name")"
  [ "$instance_status" = "Running" ] ||
    fail "Lima instance ${instance_name} must be running; current status: ${instance_status}"

  ssh_config="$(limactl list --format '{{.SSHConfigFile}}' "$instance_name")"
  [ -r "$ssh_config" ] || fail "Lima SSH config is not readable: $ssh_config"

  ssh_alias="lima-${instance_name}"
  ssh_resolved="$(ssh -G -F "$ssh_config" "$ssh_alias" 2>/dev/null)" ||
    fail "could not resolve Lima SSH configuration"
  ssh_hostname="$(printf '%s\n' "$ssh_resolved" |
    awk '$1 == "hostname" {print $2; exit}')"
  ssh_port="$(printf '%s\n' "$ssh_resolved" |
    awk '$1 == "port" {print $2; exit}')"
  ssh_user="$(printf '%s\n' "$ssh_resolved" |
    awk '$1 == "user" {print $2; exit}')"

  case "$ssh_hostname" in
    127.0.0.1|localhost|::1) ;;
    *) fail "Lima SSH must resolve to a loopback address; found ${ssh_hostname}" ;;
  esac
  case "$ssh_port" in
    ''|*[!0-9]*) fail "Lima SSH port is invalid: ${ssh_port}" ;;
  esac
  [ "$ssh_port" -ge 1 ] && [ "$ssh_port" -le 65535 ] ||
    fail "Lima SSH port is invalid: ${ssh_port}"
  case "$ssh_user" in
    ''|*[!A-Za-z0-9_.-]*) fail "Lima SSH user is invalid: ${ssh_user}" ;;
  esac

  ssh -F "$ssh_config" -o BatchMode=yes -o ConnectTimeout=10 \
    "$ssh_alias" true || fail "Lima SSH readiness check failed"

  umask 077
  mkdir -p "$cache_dir"
  jq -n \
    --arg target "$inventory_host" \
    --arg host "$ssh_alias" \
    --arg controller_host "$ssh_hostname" \
    --arg user "$ssh_user" \
    --argjson port "$ssh_port" \
    --arg ssh_config "$ssh_config" '{
      all: {
        children: {
          incus_hosts: {
            hosts: {
              ($target): {
                ansible_host: $host,
                ansible_user: $user,
                ansible_port: $port,
                ansible_ssh_args: "-o ControlMaster=no -o ControlPath=none",
                ansible_ssh_common_args: ("-F " + ($ssh_config | @sh)),
                rpr_controller_ssh_host: $controller_host,
                debian_prepare_stable_target: true
              }
            }
          }
        }
      }
    }' >"$inventory_file"

  echo "Lima inventory ready: $inventory_file"
  echo "Use PROFILE=workstation-validation INVENTORY=$inventory_file TARGET_HOST=$inventory_host"
}

case "$action" in
  validate)
    require_lima
    limactl validate "$template"
    ;;
  up)
    require_profile
    [ "${CONFIRM:-}" = "create-${instance_name}" ] ||
      fail "set CONFIRM=create-${instance_name} to create the disposable VM"
    require_lima
    if instance_exists; then
      fail "Lima instance ${instance_name} already exists"
    fi
    limactl start --tty=false --name "$instance_name" "$template"
    ;;
  start)
    require_profile
    [ "${CONFIRM:-}" = "start-${instance_name}" ] ||
      fail "set CONFIRM=start-${instance_name} to start the disposable VM"
    require_lima
    instance_exists || fail "Lima instance ${instance_name} does not exist"
    [ "$(limactl list --format '{{.Status}}' "$instance_name")" != "Running" ] ||
      fail "Lima instance ${instance_name} is already running"
    limactl start --tty=false "$instance_name"
    ;;
  stop)
    require_profile
    require_lima
    instance_exists || fail "Lima instance ${instance_name} does not exist"
    limactl stop --tty=false "$instance_name"
    ;;
  inventory)
    require_profile
    require_lima
    instance_exists || fail "Lima instance ${instance_name} does not exist"
    generate_inventory
    ;;
  delete)
    require_profile
    [ "${CONFIRM:-}" = "delete-${instance_name}" ] ||
      fail "set CONFIRM=delete-${instance_name} to delete the disposable VM"
    require_lima
    instance_exists || fail "Lima instance ${instance_name} does not exist"
    limactl delete --tty=false "$instance_name"
    ;;
  *)
    fail "usage: $0 {validate|up|start|stop|inventory|delete}"
    ;;
esac
