#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

profile=${PROFILE:-}
secrets_file=${PRIVATE_DNS_SECRETS_FILE:-"$PWD/.cache/private-dns/tsig.auto.tfvars.json"}

fail()
{
  echo "Error: $*" >&2
  exit 1
}

case "$profile" in
  workstation-validation|single-node-reference) ;;
  *) fail "set PROFILE to workstation-validation or single-node-reference" ;;
esac

[ "${CONFIRM:-}" = "generate-private-dns-tsig-${profile}" ] ||
  fail "set CONFIRM=generate-private-dns-tsig-${profile}"
case "$secrets_file" in
  /*) ;;
  *) fail "PRIVATE_DNS_SECRETS_FILE must be an absolute path" ;;
esac
[ ! -e "$secrets_file" ] ||
  fail "refusing to overwrite existing private DNS secrets: $secrets_file"

for tool in jq openssl; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

umask 077
mkdir -p "$(dirname "$secrets_file")"
jq -n \
  --arg dns_01_forward "$(openssl rand -base64 32)" \
  --arg dns_01_reverse "$(openssl rand -base64 32)" \
  --arg dns_02_forward "$(openssl rand -base64 32)" \
  --arg dns_02_reverse "$(openssl rand -base64 32)" '{
    private_dns_tsig_secrets: {
      "dns-01": {
        forward: $dns_01_forward,
        reverse: $dns_01_reverse
      },
      "dns-02": {
        forward: $dns_02_forward,
        reverse: $dns_02_reverse
      }
    }
  }' >"$secrets_file"
chmod 600 "$secrets_file"

echo "Protected private DNS TSIG input created: $secrets_file"
echo "It is synthetic, environment-specific, ignored by Git, and required for plan, apply, and BIND configuration."
