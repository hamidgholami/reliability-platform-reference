#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

action=${1:-}
profile=${PROFILE:-}
config_dir=${INCUS_CONFIG_DIR:-}
remote=${INCUS_REMOTE:-}
endpoint=${INCUS_ENDPOINT:-}
expected_fingerprint=${INCUS_SERVER_CERTIFICATE_SHA256:-}
terraform_root="infrastructure/incus"
cache_dir=${RPR_INCUS_CACHE_DIR:-"$PWD/.cache/incus-substrate"}
runtime_vars="$cache_dir/runtime.auto.tfvars.json"
state_file="$cache_dir/terraform.tfstate"
trust_plan="$cache_dir/trust.tfplan"
session_file="$cache_dir/session.json"

fail()
{
  echo "Error: $*" >&2
  exit 1
}

require_tool()
{
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

require_profile()
{
  case "$profile" in
    workstation-validation|single-node-reference) ;;
    *) fail "set PROFILE to workstation-validation or single-node-reference" ;;
  esac
}

normalize_fingerprint()
{
  printf '%s' "$1" |
    sed 's/^.*=//' |
    tr -d ':' |
    tr '[:upper:]' '[:lower:]'
}

validate_inputs()
{
  [ -n "$config_dir" ] ||
    fail "set INCUS_CONFIG_DIR to the isolated OpenTofu client configuration"
  case "$config_dir" in
    /*) ;;
    *) fail "INCUS_CONFIG_DIR must be an absolute path" ;;
  esac
  [ "$config_dir" != "$HOME/.config/incus" ] ||
    fail "OpenTofu must not use the default human Incus client identity"
  [ "$config_dir" != "$HOME/Library/Application Support/incus" ] ||
    fail "OpenTofu must not use the default human Incus client identity"

  [ -n "$remote" ] || fail "set INCUS_REMOTE to the pre-enrolled remote name"
  case "$remote" in
    *[!A-Za-z0-9_.-]*|'') fail "INCUS_REMOTE contains unsupported characters" ;;
  esac

  case "$endpoint" in
    https://*) ;;
    *) fail "INCUS_ENDPOINT must be an explicit HTTPS URL" ;;
  esac
  case "$endpoint" in
    *[[:space:],]*) fail "INCUS_ENDPOINT must contain one address without whitespace" ;;
  esac
  if [ "$profile" = "workstation-validation" ]; then
    [ "$endpoint" = "https://127.0.0.1:18443" ] ||
      fail "workstation-validation requires INCUS_ENDPOINT=https://127.0.0.1:18443"
  fi

  normalized_expected="$(normalize_fingerprint "$expected_fingerprint")"
  case "$normalized_expected" in
    *[!0-9a-f]*|'') fail "INCUS_SERVER_CERTIFICATE_SHA256 must be one SHA-256 fingerprint" ;;
  esac
  [ "${#normalized_expected}" -eq 64 ] ||
    fail "INCUS_SERVER_CERTIFICATE_SHA256 must be one SHA-256 fingerprint"
}

verify_client_trust()
{
  for tool in incus jq openssl sed tr; do
    require_tool "$tool"
  done

  for path in \
    "$config_dir/config.yml" \
    "$config_dir/client.crt" \
    "$config_dir/client.key" \
    "$config_dir/servercerts/${remote}.crt"; do
    [ -r "$path" ] || fail "required OpenTofu Incus client file is missing: $path"
  done

  remote_config="$(INCUS_CONF="$config_dir" incus remote list --format json)"
  configured_endpoint="$(printf '%s' "$remote_config" |
    jq -er --arg remote "$remote" '.[$remote].Addrs | select(length == 1) | .[0]')" ||
    fail "INCUS_REMOTE does not identify one configured Incus API endpoint"
  [ "$configured_endpoint" = "$endpoint" ] ||
    fail "configured remote endpoint does not match INCUS_ENDPOINT"

  actual_fingerprint="$(openssl x509 \
    -in "$config_dir/servercerts/${remote}.crt" \
    -noout -fingerprint -sha256)" ||
    fail "could not read the pinned Incus server certificate"
  normalized_actual="$(normalize_fingerprint "$actual_fingerprint")"
  [ "$normalized_actual" = "$normalized_expected" ] ||
    fail "pinned Incus server certificate does not match the reviewed fingerprint"

  certificate_public_key="$(openssl x509 -in "$config_dir/client.crt" \
    -pubkey -noout | openssl pkey -pubin -outform DER 2>/dev/null |
    openssl dgst -sha256)" || fail "could not inspect the client certificate"
  private_public_key="$(openssl pkey -in "$config_dir/client.key" \
    -pubout -outform DER 2>/dev/null | openssl dgst -sha256)" ||
    fail "OpenTofu requires a readable non-interactive client key"
  [ "$certificate_public_key" = "$private_public_key" ] ||
    fail "the OpenTofu Incus client certificate and key do not match"

  server_response="$(INCUS_CONF="$config_dir" incus query "${remote}:/1.0")" ||
    fail "the OpenTofu Incus client cannot query the configured remote"
  server_metadata="$(printf '%s' "$server_response" | jq -cer '
    if type == "object" and (.metadata? | type) == "object"
    then .metadata
    else .
    end
  ')" || fail "the Incus API returned an unexpected response"
  server_auth="$(printf '%s' "$server_metadata" | jq -r '.auth // empty')"
  [ "$server_auth" = "trusted" ] ||
    fail "the OpenTofu Incus client is not trusted"
  server_clustered="$(printf '%s' "$server_metadata" | jq -r '
    if .environment.server_clustered == true then "true"
    elif .environment.server_clustered == false then "false"
    else "unknown"
    end
  ')"
  [ "$server_clustered" = "false" ] ||
    fail "Phase 1 requires a standalone Incus server"

  echo "Incus provider trust verified: profile=$profile remote=$remote endpoint=$endpoint"
  echo "Server certificate SHA-256: $normalized_actual"
}

plan()
{
  require_tool shasum
  require_tool tofu
  [ -d "$terraform_root/.terraform" ] ||
    fail "run make setup-hcl before planning Incus resources"
  verify_client_trust

  umask 077
  mkdir -p "$cache_dir"
  jq -n \
    --arg profile "$profile" \
    --arg config_dir "$config_dir" \
    --arg remote "$remote" '{
      deployment_profile: $profile,
      incus_config_dir: $config_dir,
      incus_remote: $remote
    }' >"$runtime_vars"

  tofu -chdir="$terraform_root" plan \
    -input=false \
    -state="$state_file" \
    -var-file="$runtime_vars" \
    -out="$trust_plan"
  plan_sha="$(shasum -a 256 "$trust_plan" | awk '{print $1}')"
  jq -n \
    --arg profile "$profile" \
    --arg remote "$remote" \
    --arg endpoint "$endpoint" \
    --arg fingerprint "$normalized_expected" \
    --arg plan_sha "$plan_sha" '{
      schema_version: 1,
      deployment_profile: $profile,
      remote: $remote,
      endpoint: $endpoint,
      server_certificate_sha256: $fingerprint,
      plan_sha256: $plan_sha
    }' >"$session_file"

  echo "Saved read-only provider plan: $trust_plan"
  echo "P1-05 resource apply remains disabled until the substrate slice is implemented."
}

require_profile
validate_inputs
case "$action" in
  preflight) verify_client_trust ;;
  plan) plan ;;
  *) fail "usage: $0 {preflight|plan}" ;;
esac
