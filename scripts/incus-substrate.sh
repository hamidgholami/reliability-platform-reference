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
platform_ipv4_cidr=${INCUS_IPV4_CIDR:-10.20.0.0/24}
platform_dns_domain=${INCUS_DNS_DOMAIN:-dev.apadanalab.de}
instance_image=${INCUS_IMAGE:-images:debian/13}
terraform_root="infrastructure/incus"
cache_dir=${RPR_INCUS_CACHE_DIR:-"$PWD/.cache/incus-substrate"}
runtime_vars="$cache_dir/runtime.auto.tfvars.json"
state_file="$cache_dir/terraform.tfstate"
create_plan="$cache_dir/create.tfplan"
destroy_plan="$cache_dir/destroy.tfplan"
session_file="$cache_dir/session.json"
inventory_file="$cache_dir/inventory.json"
evidence_file="$cache_dir/validation.json"

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

verify_server_capabilities()
{
  required_extensions="
projects_restrictions
projects_networks_restricted_access
projects_limits_disk_pool
storage_api_project
"

  for extension in $required_extensions; do
    printf '%s' "$server_metadata" |
      jq -e --arg extension "$extension" \
        '.api_extensions | index($extension) != null' >/dev/null ||
      fail "the Incus server lacks required API extension: $extension"
  done

  server_version="$(printf '%s' "$server_metadata" |
    jq -er '.environment.server_version')" ||
    fail "the Incus API did not report its server version"
  echo "Incus substrate capabilities verified: server=$server_version"
}

write_runtime_vars()
{
  umask 077
  mkdir -p "$cache_dir"
  jq -n \
    --arg profile "$profile" \
    --arg config_dir "$config_dir" \
    --arg remote "$remote" \
    --arg ipv4_cidr "$platform_ipv4_cidr" \
    --arg dns_domain "$platform_dns_domain" \
    --arg image "$instance_image" '{
      deployment_profile: $profile,
      incus_config_dir: $config_dir,
      incus_remote: $remote,
      platform_ipv4_cidr: $ipv4_cidr,
      platform_dns_domain: $dns_domain,
      instance_image: $image
    }' >"$runtime_vars"
}

load_session()
{
  require_tool shasum
  [ -r "$session_file" ] ||
    fail "no planned Incus session exists; run make plan first"
  [ -r "$runtime_vars" ] ||
    fail "planned Incus runtime inputs are missing; run make plan again"

  session_profile="$(jq -er '.deployment_profile' "$session_file")" ||
    fail "planned Incus session is invalid"
  session_remote="$(jq -er '.remote' "$session_file")" ||
    fail "planned Incus session is invalid"
  session_endpoint="$(jq -er '.endpoint' "$session_file")" ||
    fail "planned Incus session is invalid"
  session_fingerprint="$(jq -er '.server_certificate_sha256' "$session_file")" ||
    fail "planned Incus session is invalid"
  session_ipv4_cidr="$(jq -er '.platform_ipv4_cidr' "$session_file")" ||
    fail "planned Incus session is invalid"
  session_dns_domain="$(jq -er '.platform_dns_domain' "$session_file")" ||
    fail "planned Incus session is invalid"
  session_image="$(jq -er '.instance_image' "$session_file")" ||
    fail "planned Incus session is invalid"
  expected_runtime_sha="$(jq -er '.runtime_vars_sha256' "$session_file")" ||
    fail "planned Incus session has no runtime-input digest"

  [ "$profile" = "$session_profile" ] ||
    fail "PROFILE does not match the reviewed Incus plan"
  [ "$remote" = "$session_remote" ] ||
    fail "INCUS_REMOTE does not match the reviewed Incus plan"
  [ "$endpoint" = "$session_endpoint" ] ||
    fail "INCUS_ENDPOINT does not match the reviewed Incus plan"
  [ "$normalized_expected" = "$session_fingerprint" ] ||
    fail "the server fingerprint does not match the reviewed Incus plan"
  actual_runtime_sha="$(shasum -a 256 "$runtime_vars" | awk '{print $1}')"
  [ "$actual_runtime_sha" = "$expected_runtime_sha" ] ||
    fail "planned Incus runtime inputs changed after review; run make plan again"
}

verify_create_plan()
{
  require_tool shasum
  [ -r "$create_plan" ] || fail "saved create plan is missing; run make plan"
  expected_sha="$(jq -er '.create_plan_sha256' "$session_file")" ||
    fail "planned Incus session has no create-plan digest"
  actual_sha="$(shasum -a 256 "$create_plan" | awk '{print $1}')"
  [ "$actual_sha" = "$expected_sha" ] ||
    fail "saved create plan changed after review; run make plan again"
}

plan()
{
  require_tool shasum
  require_tool tofu
  [ -d "$terraform_root/.terraform" ] ||
    fail "run make setup-hcl before planning Incus resources"
  verify_client_trust
  verify_server_capabilities
  write_runtime_vars

  tofu -chdir="$terraform_root" plan \
    -input=false \
    -state="$state_file" \
    -var-file="$runtime_vars" \
    -out="$create_plan"
  plan_json="$(tofu -chdir="$terraform_root" show -json "$create_plan")"
  destructive_count="$(printf '%s' "$plan_json" | jq '[
    .resource_changes[]?
    | select(.mode == "managed")
    | select(.change.actions | index("delete"))
  ] | length')"
  [ "$destructive_count" -eq 0 ] ||
    fail "the create plan contains destructive actions; use the replacement or destroy workflow"
  action_summary="$(printf '%s' "$plan_json" | jq -c '[
    .resource_changes[]?
    | select(.mode == "managed")
    | {address, actions: .change.actions}
  ]')"
  plan_sha="$(shasum -a 256 "$create_plan" | awk '{print $1}')"
  runtime_sha="$(shasum -a 256 "$runtime_vars" | awk '{print $1}')"
  jq -n \
    --arg profile "$profile" \
    --arg remote "$remote" \
    --arg endpoint "$endpoint" \
    --arg fingerprint "$normalized_expected" \
    --arg ipv4_cidr "$platform_ipv4_cidr" \
    --arg dns_domain "$platform_dns_domain" \
    --arg image "$instance_image" \
    --arg server_version "$server_version" \
    --arg runtime_sha "$runtime_sha" \
    --arg plan_sha "$plan_sha" \
    --argjson actions "$action_summary" '{
      schema_version: 1,
      deployment_profile: $profile,
      remote: $remote,
      endpoint: $endpoint,
      server_certificate_sha256: $fingerprint,
      platform_ipv4_cidr: $ipv4_cidr,
      platform_dns_domain: $dns_domain,
      instance_image: $image,
      incus_server_version: $server_version,
      resource_changes: $actions,
      runtime_vars_sha256: $runtime_sha,
      create_plan_sha256: $plan_sha
    }' >"$session_file"

  echo "Incus substrate boundary:"
  echo "  profile: $profile"
  echo "  remote:  $remote ($endpoint)"
  echo "  network: $platform_ipv4_cidr; DNS $platform_dns_domain; IPv6 disabled"
  echo "  image:   $instance_image"
  printf '%s\n' "$action_summary" | jq -r '.[] | "  \(.actions | join("/")): \(.address)"'
  echo "Saved reviewed plan: $create_plan"
  echo "Apply confirmation: CONFIRM=apply-incus-$profile-$remote make apply"
}

write_inventory()
{
  umask 077
  outputs="$(tofu -chdir="$terraform_root" output -state="$state_file" -json)"
  printf '%s' "$outputs" | jq --arg remote "$remote" '{
    schema_version: 1,
    remote: $remote,
    project: .substrate.value.project,
    instances: [{
      name: .substrate.value.instance,
      type: .substrate.value.instance_type,
      ipv4_address: .substrate.value.instance_ipv4,
      dns_name: .substrate.value.instance_dns_name,
      status: .substrate.value.instance_status
    }]
  }' >"$inventory_file"
}

apply_plan()
{
  expected="apply-incus-$profile-$remote"
  [ "${CONFIRM:-}" = "$expected" ] ||
    fail "set CONFIRM=$expected to create the Incus substrate"
  for tool in jq shasum tofu; do
    require_tool "$tool"
  done
  load_session
  verify_create_plan
  verify_client_trust
  verify_server_capabilities

  umask 077
  echo "Applying only the reviewed Incus plan to $remote ($endpoint)."
  tofu -chdir="$terraform_root" apply \
    -input=false \
    -state="$state_file" \
    "$create_plan"
  write_inventory
  rm -f "$create_plan"
  echo "Generated ignored inventory: $inventory_file"
  echo "Run make validate, then make plan again to prove no drift."
}

validate_substrate()
{
  for tool in incus jq tofu; do
    require_tool "$tool"
  done
  load_session
  verify_client_trust
  verify_server_capabilities
  [ -r "$state_file" ] || fail "Incus state is missing; run make apply first"

  outputs="$(tofu -chdir="$terraform_root" output -state="$state_file" -json)"
  project_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.project')"
  pool_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.storage_pool')"
  network_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.network')"
  profile_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.profile')"
  instance_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.instance')"
  instance_dns_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.instance_dns_name')"
  bridge_ipv4_address="$(printf '%s' "$outputs" | jq -er '.substrate.value.bridge_ipv4_address')"
  planned_image="$(printf '%s' "$outputs" | jq -er '.substrate.value.instance_image')"
  [ "$planned_image" = "$session_image" ] ||
    fail "the state image differs from the reviewed Incus session"

  project_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/projects/${project_name}")"
  [ "$(printf '%s' "$project_json" | jq -r '.config.restricted')" = "true" ] ||
    fail "the Incus project is not restricted"
  [ "$(printf '%s' "$project_json" | jq -r '.config["limits.containers"]')" = "1" ] ||
    fail "the Incus project does not enforce the one-container limit"
  [ "$(printf '%s' "$project_json" | jq -r '.config["limits.virtual-machines"]')" = "0" ] ||
    fail "the Incus project permits virtual machines"
  [ "$(printf '%s' "$project_json" | jq -r '.config["restricted.networks.access"]')" = "$network_name" ] ||
    fail "the Incus project permits an unexpected managed network"
  [ "$(printf '%s' "$project_json" | jq -r '.config["limits.disk"]')" = "4GiB" ] ||
    fail "the Incus project aggregate disk limit differs from the Phase 1 boundary"
  [ "$(printf '%s' "$project_json" |
    jq -r --arg key "limits.disk.pool.${pool_name}" '.config[$key]')" = "4GiB" ] ||
    fail "the Incus project per-pool disk limit differs from the Phase 1 boundary"

  network_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/networks/${network_name}?project=default")"
  [ "$(printf '%s' "$network_json" | jq -r '.config["ipv4.address"]')" = "$bridge_ipv4_address" ] ||
    fail "the managed bridge IPv4 address differs from state"
  [ "$(printf '%s' "$network_json" | jq -r '.config["ipv4.dhcp"]')" = "true" ] ||
    fail "the managed bridge does not have DHCP enabled"
  [ "$(printf '%s' "$network_json" | jq -r '.config["dns.domain"]')" = "$session_dns_domain" ] ||
    fail "the managed bridge DNS suffix differs from the planned value"
  [ "$(printf '%s' "$network_json" | jq -r '.config["ipv4.nat"]')" = "true" ] ||
    fail "the managed bridge does not have IPv4 NAT enabled"
  [ "$(printf '%s' "$network_json" | jq -r '.config["ipv6.address"]')" = "none" ] ||
    fail "the managed bridge does not enforce the Phase 1 IPv6 policy"

  pool_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/storage-pools/${pool_name}?project=default")"
  [ "$(printf '%s' "$pool_json" | jq -r '.driver')" = "dir" ] ||
    fail "the Phase 1 storage pool does not use the dir driver"

  profile_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/profiles/${profile_name}?project=${project_name}")"
  [ "$(printf '%s' "$profile_json" | jq -r '.config["security.privileged"]')" = "false" ] ||
    fail "the system-container profile does not enforce unprivileged containers"
  [ "$(printf '%s' "$profile_json" | jq -r '.devices.root.pool')" = "$pool_name" ] ||
    fail "the system-container profile root disk uses the wrong pool"
  [ "$(printf '%s' "$profile_json" | jq -r '.devices.eth0.network')" = "$network_name" ] ||
    fail "the system-container profile NIC uses the wrong network"

  instance_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/instances/${instance_name}?project=${project_name}")"
  [ "$(printf '%s' "$instance_json" | jq -r '.type')" = "container" ] ||
    fail "the smoke instance is not a system container"
  state_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/instances/${instance_name}/state?project=${project_name}")"
  [ "$(printf '%s' "$state_json" | jq -r '.status')" = "Running" ] ||
    fail "the smoke container is not running"
  instance_ipv4="$(printf '%s' "$state_json" | jq -er '
    [.network.eth0.addresses[]
      | select(.family == "inet" and .scope == "global")
      | .address][0]
  ')" || fail "the smoke container has no global IPv4 address on eth0"

  INCUS_CONF="$config_dir" incus exec --project "$project_name" \
    "${remote}:${instance_name}" -- getent ahostsv4 "$instance_dns_name" >/dev/null
  INCUS_CONF="$config_dir" incus exec --project "$project_name" \
    "${remote}:${instance_name}" -- getent ahostsv4 deb.debian.org >/dev/null
  INCUS_CONF="$config_dir" incus exec --project "$project_name" \
    "${remote}:${instance_name}" -- ping -c 1 -W 5 1.1.1.1 >/dev/null

  umask 077
  jq -n \
    --arg profile "$profile" \
    --arg remote "$remote" \
    --arg project "$project_name" \
    --arg pool "$pool_name" \
    --arg network "$network_name" \
    --arg instance "$instance_name" \
    --arg ipv4 "$instance_ipv4" \
    --arg ipv4_cidr "$session_ipv4_cidr" \
    --arg dns_name "$instance_dns_name" '{
      schema_version: 1,
      deployment_profile: $profile,
      remote: $remote,
      project: $project,
      storage_pool: $pool,
      network: $network,
      instance: $instance,
      instance_ipv4: $ipv4,
      platform_ipv4_cidr: $ipv4_cidr,
      instance_dns_name: $dns_name,
      instance_running: true,
      internal_dns_resolved: true,
      external_dns_resolved: true,
      outbound_ipv4_reachable: true,
      ipv6_policy: "disabled"
    }' >"$evidence_file"
  write_inventory

  echo "Incus substrate validation passed: $instance_name ($instance_ipv4)"
  echo "Generated ignored validation evidence: $evidence_file"
}

destroy()
{
  expected="destroy-incus-$profile-$remote"
  [ "${CONFIRM:-}" = "$expected" ] ||
    fail "set CONFIRM=$expected to destroy only provider-owned Incus resources"
  for tool in jq tofu; do
    require_tool "$tool"
  done
  load_session
  verify_client_trust
  verify_server_capabilities
  [ -r "$state_file" ] || fail "Incus state is missing; nothing can be safely destroyed"

  umask 077
  echo "Planning destruction only for provider-owned resources on $remote ($endpoint)."
  tofu -chdir="$terraform_root" plan -destroy \
    -input=false \
    -state="$state_file" \
    -var-file="$runtime_vars" \
    -out="$destroy_plan"
  tofu -chdir="$terraform_root" show "$destroy_plan"
  tofu -chdir="$terraform_root" apply \
    -input=false \
    -state="$state_file" \
    "$destroy_plan"

  managed_state="$(tofu -chdir="$terraform_root" state list \
    -state="$state_file" 2>/dev/null | sed -n '/^incus_/p')"
  [ -z "$managed_state" ] || {
    printf '%s\n' "$managed_state" >&2
    fail "provider-managed Incus resources remain in state"
  }
  rm -f "$create_plan" "$destroy_plan" "$inventory_file" "$evidence_file"
  echo "Incus provider destroy finished; the Incus server remains installed and initialized."
}

require_profile
validate_inputs
case "$action" in
  preflight) verify_client_trust ;;
  plan) plan ;;
  apply) apply_plan ;;
  validate) validate_substrate ;;
  destroy) destroy ;;
  *) fail "usage: $0 {preflight|plan|apply|validate|destroy}" ;;
esac
