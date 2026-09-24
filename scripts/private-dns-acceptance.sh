#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

profile=${PROFILE:-}
config_dir=${INCUS_CONFIG_DIR:-}
remote=${INCUS_REMOTE:-}
inventory=${PRIVATE_DNS_INVENTORY:-"$PWD/.cache/incus-substrate/private-dns-hosts.json"}
evidence=${PRIVATE_DNS_EVIDENCE:-"$PWD/.cache/private-dns/acceptance.json"}
probe_record=acceptance-refresh-probe
probe_ipv4=10.20.0.220
probe_record_created=false
probe_record_touched=false

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
[ -n "$remote" ] || fail "set INCUS_REMOTE to the pre-enrolled remote name"
case "$remote" in
  *[!A-Za-z0-9_.-]*|'') fail "INCUS_REMOTE contains unsupported characters" ;;
esac
[ -r "$inventory" ] || fail "private DNS inventory is missing; run make validate"
[ "${CONFIRM:-}" = "accept-private-dns-$profile-$remote" ] ||
  fail "set CONFIRM=accept-private-dns-$profile-$remote"

for tool in awk incus jq sort; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

project="$(jq -er '.all.children.dns_secondaries.vars.ansible_incus_project' "$inventory")"
inventory_profile="$(jq -er '.all.children.dns_secondaries.vars.rpr_deployment_profile' "$inventory")"
inventory_remote="$(jq -er '.all.children.dns_secondaries.vars.ansible_incus_remote' "$inventory")"
forward_zone="$(jq -er '.all.children.dns_secondaries.vars.bind_secondary_forward_zone' "$inventory")"
automatic_name="$(jq -er '.all.children.dns_secondaries.vars.bind_secondary_expected_automatic_name' "$inventory")"
automatic_ipv4="$(jq -er '.all.children.dns_secondaries.vars.bind_secondary_expected_automatic_ipv4' "$inventory")"
manual_name="$(jq -er '.all.children.dns_secondaries.vars.bind_secondary_expected_manual_name' "$inventory")"
manual_addresses="$(jq -cer '.all.children.dns_secondaries.vars.bind_secondary_expected_manual_ipv4_addresses | sort' "$inventory")"
dns_01_ipv4="$(jq -er '.all.children.dns_secondaries.hosts["dns-01"].bind_secondary_listen_address' "$inventory")"
dns_02_ipv4="$(jq -er '.all.children.dns_secondaries.hosts["dns-02"].bind_secondary_listen_address' "$inventory")"
smoke_instance=${automatic_name%%.*}
probe_name="$probe_record.${automatic_name#*.}"

[ "$inventory_profile" = "$profile" ] || fail "inventory profile does not match PROFILE"
[ "$inventory_remote" = "$remote" ] || fail "inventory remote does not match INCUS_REMOTE"
[ "$project" = "rpr-dev" ] || fail "inventory project violates the reviewed boundary"
[ "$smoke_instance" = "smoke-01" ] || fail "the automatic-record probe must use smoke-01"
[ "$manual_addresses" = "[\"10.20.0.10\",\"10.20.0.11\"]" ] ||
  fail "manual resolver addresses violate the reviewed boundary"

incus_instance_exists()
{
  INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/instances/$1?project=${project}" >/dev/null 2>&1
}

incus_instance_status()
{
  INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/instances/$1/state?project=${project}" |
    jq -er '.status'
}

start_instance()
{
  INCUS_CONF="$config_dir" incus start --project "$project" "${remote}:$1"
}

stop_instance()
{
  INCUS_CONF="$config_dir" incus stop --project "$project" \
    "${remote}:$1" --timeout 30
}

query_a()
{
  INCUS_CONF="$config_dir" incus exec --project "$project" \
    "${remote}:$1" -- dig "@$2" "$3" A +norecurse +short
}

query_ptr()
{
  INCUS_CONF="$config_dir" incus exec --project "$project" \
    "${remote}:$1" -- dig "@$2" -x "$3" +norecurse +short
}

zone_record_exists()
{
  INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/network-zones/${forward_zone}/records/$1?project=${project}" \
    >/dev/null 2>&1
}

create_probe_record()
{
  payload="$(jq -nc \
    --arg name "$probe_record" \
    --arg ipv4 "$probe_ipv4" '{
      name: $name,
      description: "Temporary private DNS acceptance probe",
      entries: [{type: "A", value: $ipv4, ttl: 60}],
      config: {}
    }')"
  INCUS_CONF="$config_dir" incus query -X POST -d "$payload" \
    "${remote}:/1.0/network-zones/${forward_zone}/records?project=${project}" \
    >/dev/null
}

delete_probe_record()
{
  INCUS_CONF="$config_dir" incus query -X DELETE \
    "${remote}:/1.0/network-zones/${forward_zone}/records/${probe_record}?project=${project}" \
    >/dev/null
}

query_serial()
{
  INCUS_CONF="$config_dir" incus exec --project "$project" \
    "${remote}:$1" -- dig "@$2" "$forward_zone" SOA +norecurse +short |
    awk '{print $3}'
}

query_refresh_interval()
{
  INCUS_CONF="$config_dir" incus exec --project "$project" \
    "${remote}:$1" -- dig "@$2" "$forward_zone" SOA +norecurse +short |
    awk '{print $4}'
}

force_zone_refresh()
{
  INCUS_CONF="$config_dir" incus exec --project "$project" \
    "${remote}:$1" -- rndc refresh "$forward_zone" >/dev/null
}

wait_for_a()
{
  attempt=0
  max_attempts=${6:-30}
  while [ "$attempt" -lt "$max_attempts" ]; do
    answer="$(query_a "$1" "$2" "$3" 2>/dev/null | sort || true)"
    [ "$answer" = "$4" ] && return 0
    attempt=$((attempt + 1))
    sleep 1
  done
  fail "$5 did not reach the expected A answer for $3 (got: ${answer:-<empty>})"
}

wait_for_ptr()
{
  attempt=0
  while [ "$attempt" -lt 30 ]; do
    answer="$(query_ptr "$1" "$2" "$3" 2>/dev/null | sort || true)"
    [ "$answer" = "$4" ] && return 0
    attempt=$((attempt + 1))
    sleep 1
  done
  fail "$5 did not reach the expected PTR answer for $3 (got: ${answer:-<empty>})"
}

wait_for_absent_a()
{
  attempt=0
  while [ "$attempt" -lt 30 ]; do
    answer="$(query_a "$1" "$2" "$3" 2>/dev/null | sort || true)"
    [ -z "$answer" ] && return 0
    attempt=$((attempt + 1))
    sleep 1
  done
  fail "$4 retained the removed temporary A record"
}

cleanup()
{
  result=$?
  trap - 0 1 2 15
  if [ "$probe_record_created" = "true" ] && zone_record_exists "$probe_record"; then
    delete_probe_record >/dev/null 2>&1 || true
  fi
  for instance in "$smoke_instance" dns-01 dns-02; do
    if incus_instance_exists "$instance" &&
      [ "$(incus_instance_status "$instance" 2>/dev/null || true)" != "Running" ]; then
      start_instance "$instance" >/dev/null 2>&1 || true
    fi
  done
  if [ "$result" -ne 0 ] && [ "$probe_record_touched" = "true" ]; then
    force_zone_refresh dns-01 >/dev/null 2>&1 || true
    force_zone_refresh dns-02 >/dev/null 2>&1 || true
  fi
  exit "$result"
}
trap cleanup 0 1 2 15

zone_record_exists "$probe_record" &&
  fail "temporary acceptance record already exists: $probe_record"
for instance in "$smoke_instance" dns-01 dns-02; do
  incus_instance_exists "$instance" || fail "required instance is missing: $instance"
  [ "$(incus_instance_status "$instance")" = "Running" ] ||
    fail "required instance is not running: $instance"
done

echo "Checking current automatic and manual answers through both secondaries."
for dns_name in dns-01 dns-02; do
  case "$dns_name" in
    dns-01) dns_ipv4=$dns_01_ipv4 ;;
    dns-02) dns_ipv4=$dns_02_ipv4 ;;
  esac
  wait_for_a "$dns_name" "$dns_ipv4" "$automatic_name" "$automatic_ipv4" "$dns_name initial"
  wait_for_ptr "$dns_name" "$dns_ipv4" "$automatic_ipv4" "$automatic_name." "$dns_name initial"
  wait_for_a "$dns_name" "$dns_ipv4" "$manual_name" "$(printf '%s' "$manual_addresses" | jq -r '.[]')" "$dns_name initial"
done

refresh_interval_01="$(query_refresh_interval dns-01 "$dns_01_ipv4")"
refresh_interval_02="$(query_refresh_interval dns-02 "$dns_02_ipv4")"
[ "$refresh_interval_01" = "120" ] ||
  fail "dns-01 advertises an unexpected SOA refresh interval"
[ "$refresh_interval_02" = "120" ] ||
  fail "dns-02 advertises an unexpected SOA refresh interval"
force_zone_refresh dns-01
force_zone_refresh dns-02
sleep 2
serial_before_01="$(query_serial dns-01 "$dns_01_ipv4")"
serial_before_02="$(query_serial dns-02 "$dns_02_ipv4")"
echo "Creating one temporary record to exercise the Incus 6.0 LTS SOA refresh path."
create_probe_record
probe_record_created=true
probe_record_touched=true

for dns_name in dns-01 dns-02; do
  case "$dns_name" in
    dns-01) dns_ipv4=$dns_01_ipv4 ;;
    dns-02) dns_ipv4=$dns_02_ipv4 ;;
  esac
  wait_for_a "$dns_name" "$dns_ipv4" "$probe_name" "$probe_ipv4" "$dns_name added" 150
done
serial_after_add_01="$(query_serial dns-01 "$dns_01_ipv4")"
serial_after_add_02="$(query_serial dns-02 "$dns_02_ipv4")"
[ "$serial_after_add_01" != "$serial_before_01" ] ||
  fail "dns-01 forward-zone serial did not change after adding the probe"
[ "$serial_after_add_02" != "$serial_before_02" ] ||
  fail "dns-02 forward-zone serial did not change after adding the probe"

echo "Removing the temporary record and forcing an authenticated cleanup refresh."
delete_probe_record
probe_record_created=false
force_zone_refresh dns-01
force_zone_refresh dns-02
for dns_name in dns-01 dns-02; do
  case "$dns_name" in
    dns-01) dns_ipv4=$dns_01_ipv4 ;;
    dns-02) dns_ipv4=$dns_02_ipv4 ;;
  esac
  wait_for_absent_a "$dns_name" "$dns_ipv4" "$probe_name" "$dns_name"
done
serial_after_remove_01="$(query_serial dns-01 "$dns_01_ipv4")"
serial_after_remove_02="$(query_serial dns-02 "$dns_02_ipv4")"
[ "$serial_after_remove_01" != "$serial_after_add_01" ] ||
  fail "dns-01 forward-zone serial did not change after removing the probe"
[ "$serial_after_remove_02" != "$serial_after_add_02" ] ||
  fail "dns-02 forward-zone serial did not change after removing the probe"

echo "Stopping each DNS secondary in turn and querying the survivor."
stop_instance dns-01
wait_for_a dns-02 "$dns_02_ipv4" "$automatic_name" "$automatic_ipv4" dns-02
wait_for_a dns-02 "$dns_02_ipv4" "$manual_name" "$(printf '%s' "$manual_addresses" | jq -r '.[]')" dns-02
start_instance dns-01
wait_for_a dns-01 "$dns_01_ipv4" "$automatic_name" "$automatic_ipv4" dns-01

stop_instance dns-02
wait_for_a dns-01 "$dns_01_ipv4" "$automatic_name" "$automatic_ipv4" dns-01
wait_for_a dns-01 "$dns_01_ipv4" "$manual_name" "$(printf '%s' "$manual_addresses" | jq -r '.[]')" dns-01
start_instance dns-02
wait_for_a dns-02 "$dns_02_ipv4" "$automatic_name" "$automatic_ipv4" dns-02

umask 077
mkdir -p "$(dirname "$evidence")"
jq -n \
  --arg profile "$profile" \
  --arg remote "$remote" \
  --arg project "$project" \
  --arg forward_zone "$forward_zone" \
  --arg automatic_name "$automatic_name" \
  --arg automatic_ipv4 "$automatic_ipv4" \
  --arg manual_name "$manual_name" \
  --argjson manual_addresses "$manual_addresses" \
  --arg serial_before_01 "$serial_before_01" \
  --arg serial_before_02 "$serial_before_02" \
  --arg serial_after_add_01 "$serial_after_add_01" \
  --arg serial_after_add_02 "$serial_after_add_02" \
  --arg serial_after_remove_01 "$serial_after_remove_01" \
  --arg serial_after_remove_02 "$serial_after_remove_02" '{
    schema_version: 1,
    deployment_profile: $profile,
    remote: $remote,
    project: $project,
    forward_zone: $forward_zone,
    automatic_record: {name: $automatic_name, ipv4_address: $automatic_ipv4},
    manual_record: {name: $manual_name, ipv4_addresses: $manual_addresses},
    zone_serials: {
      "dns-01": {
        before: $serial_before_01,
        after_add: $serial_after_add_01,
        after_remove: $serial_after_remove_01
      },
      "dns-02": {
        before: $serial_before_02,
        after_add: $serial_after_add_02,
        after_remove: $serial_after_remove_02
      }
    },
    soa_refresh_interval_seconds: 120,
    periodic_refresh_passed: true,
    cleanup_refresh_forced: true,
    automatic_forward_reverse_answers_passed: true,
    temporary_record_removed: true,
    individual_secondary_stop_passed: true,
    provider_owned_instances_unchanged: true
  }' >"$evidence"

echo "Private DNS runtime acceptance passed through both secondaries."
echo "Generated ignored acceptance evidence: $evidence"
