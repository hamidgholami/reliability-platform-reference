#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

audit_dir=/var/log/openbao
audit_file=/var/log/openbao/audit.log
rotation_config=/etc/logrotate.d/openbao-audit
unit=openbao.service
api_name=openbao.dev.apadanalab.de
api_address=10.20.0.20
api_port=8200
ca_file=/opt/openbao/tls/ca.crt
probe_url="https://$api_name:$api_port/v1/rpr-audit-acceptance"
health_url="https://$api_name:$api_port/v1/sys/health"
audit_disrupted=0

fail()
{
  echo "Error: $*" >&2
  exit 1
}

curl_status()
{
  url=$1
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --noproxy '*' \
    --cacert "$ca_file" \
    --resolve "$api_name:$api_port:$api_address" \
    --connect-timeout 3 \
    --max-time 5 \
    "$url"
}

assert_audit_file()
{
  [ -f "$audit_file" ] || fail "the active audit log is missing"
  [ "$(stat -c '%a' "$audit_file")" = "600" ] ||
    fail "the active audit log must use mode 0600"
  [ "$(stat -c '%U:%G' "$audit_file")" = "openbao:openbao" ] ||
    fail "the active audit log must belong to openbao:openbao"
  [ "$(stat -c '%a' "$audit_dir")" = "700" ] ||
    fail "the audit directory must use mode 0700"
  [ "$(stat -c '%U:%G' "$audit_dir")" = "openbao:openbao" ] ||
    fail "the audit directory must belong to openbao:openbao"
}

restore_audit_path()
{
  chmod 0700 "$audit_dir"
  chown openbao:openbao "$audit_dir"
  chown openbao:openbao "$audit_file"
  chmod 0600 "$audit_file"
  systemctl kill --kill-who=main --signal=HUP "$unit"
  audit_disrupted=0
}

cleanup()
{
  if [ "$audit_disrupted" -eq 1 ]; then
    echo "Restoring the OpenBao audit path after an interrupted exercise..." >&2
    chmod 0700 "$audit_dir" >/dev/null 2>&1 || true
    chown openbao:openbao "$audit_dir" >/dev/null 2>&1 || true
    chown openbao:openbao "$audit_file" >/dev/null 2>&1 || true
    chmod 0600 "$audit_file" >/dev/null 2>&1 || true
    systemctl kill --kill-who=main --signal=HUP "$unit" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

for tool in curl logrotate stat systemctl wc; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done
[ "$(id -u)" -eq 0 ] || fail "the audit exercise must run as root"
[ -r "$rotation_config" ] || fail "the OpenBao logrotate policy is missing"
systemctl is-active --quiet "$unit" || fail "OpenBao is not active"

health_code=$(curl_status "$health_url") || fail "OpenBao health is unreachable"
[ "$health_code" = "200" ] || fail "OpenBao must be initialized and unsealed"
assert_audit_file

initial_inode=$(stat -c '%i' "$audit_file")
initial_size=$(stat -c '%s' "$audit_file")
initial_lines=$(wc -l <"$audit_file")
probe_code=$(curl_status "$probe_url") || fail "the initial audited probe failed"
[ "$probe_code" = "403" ] || fail "the synthetic unauthenticated probe must be denied"
after_probe_size=$(stat -c '%s' "$audit_file")
after_probe_lines=$(wc -l <"$audit_file")
[ "$after_probe_size" -gt "$initial_size" ] || fail "the audit log did not grow"
[ "$after_probe_lines" -ge $((initial_lines + 2)) ] ||
  fail "the audit log did not record request and response entries"

logrotate --force "$rotation_config"
[ -f "$audit_file.1" ] || fail "forced rotation did not retain the prior audit log"
[ "$(stat -c '%i' "$audit_file.1")" = "$initial_inode" ] ||
  fail "forced rotation did not move the original audit log"
[ "$(stat -c '%a' "$audit_file.1")" = "600" ] ||
  fail "the rotated audit log must retain mode 0600"
[ "$(stat -c '%U:%G' "$audit_file.1")" = "openbao:openbao" ] ||
  fail "the rotated audit log must remain owned by openbao:openbao"
assert_audit_file
[ "$(stat -c '%i' "$audit_file")" != "$initial_inode" ] ||
  fail "forced rotation did not create a new active audit log"

rotated_probe_code=$(curl_status "$probe_url") ||
  fail "the post-rotation audited probe failed"
[ "$rotated_probe_code" = "403" ] ||
  fail "the post-rotation synthetic probe must be denied"
rotated_active_lines=$(wc -l <"$audit_file")
[ "$rotated_active_lines" -ge 2 ] ||
  fail "audit writes did not continue after rotation"

audit_disrupted=1
chown root:root "$audit_file" "$audit_dir"
chmod 0400 "$audit_file"
chmod 0500 "$audit_dir"
systemctl kill --kill-who=main --signal=HUP "$unit"
sleep 1

blocked_health_code=$(curl_status "$health_url") ||
  fail "the excluded health endpoint failed during the audit exercise"
[ "$blocked_health_code" = "200" ] ||
  fail "OpenBao became unhealthy instead of isolating the audit failure"

set +e
blocked_probe_code=$(curl_status "$probe_url")
blocked_probe_rc=$?
set -e
case "$blocked_probe_rc:$blocked_probe_code" in
  0:500|28:000) ;;
  *) fail "an audited request did not fail closed while the device was unavailable" ;;
esac

restore_audit_path
sleep 1
assert_audit_file
systemctl is-active --quiet "$unit" || fail "OpenBao is not active after restoration"
restored_health_code=$(curl_status "$health_url") ||
  fail "OpenBao health did not recover after audit restoration"
[ "$restored_health_code" = "200" ] ||
  fail "OpenBao is not healthy after audit restoration"

restored_size=$(stat -c '%s' "$audit_file")
restored_probe_code=$(curl_status "$probe_url") ||
  fail "the restored audited probe failed"
[ "$restored_probe_code" = "403" ] ||
  fail "the restored synthetic probe must be denied"
[ "$(stat -c '%s' "$audit_file")" -gt "$restored_size" ] ||
  fail "audit writes did not resume after restoration"

echo "OpenBao audit acceptance passed: protected writes, rotation continuity, fail-closed behavior, and restoration are verified."
