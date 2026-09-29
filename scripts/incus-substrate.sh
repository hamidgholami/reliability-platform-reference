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
ssh_test_enabled=${SSH_TEST_ENABLED:-false}
ssh_test_acl_retained=${SSH_TEST_ACL_RETAINED:-false}
terraform_root="infrastructure/incus"
cache_dir=${RPR_INCUS_CACHE_DIR:-"$PWD/.cache/incus-substrate"}
runtime_vars="$cache_dir/runtime.auto.tfvars.json"
state_file="$cache_dir/terraform.tfstate"
create_plan="$cache_dir/create.tfplan"
destroy_plan="$cache_dir/destroy.tfplan"
session_file="$cache_dir/session.json"
inventory_file="$cache_dir/inventory.json"
evidence_file="$cache_dir/validation.json"
private_dns_secrets_file=${PRIVATE_DNS_SECRETS_FILE:-"$PWD/.cache/private-dns/tsig.auto.tfvars.json"}
private_dns_inventory_file="$cache_dir/private-dns-hosts.json"
openbao_inventory_file="$cache_dir/openbao-hosts.json"

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
  case "$ssh_test_enabled" in
    true|false) ;;
    *) fail "SSH_TEST_ENABLED must be true or false" ;;
  esac
  case "$ssh_test_acl_retained" in
    true|false) ;;
    *) fail "SSH_TEST_ACL_RETAINED must be true or false" ;;
  esac
  [ "$ssh_test_enabled" = "false" ] || [ "$ssh_test_acl_retained" = "false" ] ||
    fail "SSH_TEST_ACL_RETAINED is only for retirement"
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

validate_private_dns_secrets()
{
  case "$private_dns_secrets_file" in
    /*) ;;
    *) fail "PRIVATE_DNS_SECRETS_FILE must be an absolute path" ;;
  esac
  [ -r "$private_dns_secrets_file" ] ||
    fail "private DNS secrets are missing; run make private-dns-secrets"
  secret_mode="$(stat -f '%Lp' "$private_dns_secrets_file" 2>/dev/null ||
    stat -c '%a' "$private_dns_secrets_file")"
  [ "$secret_mode" = "600" ] ||
    fail "private DNS secrets must use mode 0600"
  jq -e '
    .private_dns_tsig_secrets as $secrets
    | ($secrets | type) == "object"
    and ($secrets | keys | length) == 2
    and ($secrets | has("dns-01"))
    and ($secrets | has("dns-02"))
    and (["dns-01", "dns-02"] | all(
      ($secrets[.].forward | type) == "string"
      and ($secrets[.].reverse | type) == "string"
      and ($secrets[.].forward | length) >= 32
      and ($secrets[.].reverse | length) >= 32
      and ($secrets[.].forward | test("\\s") | not)
      and ($secrets[.].reverse | test("\\s") | not)
    ))
  ' "$private_dns_secrets_file" >/dev/null ||
    fail "private DNS secrets do not satisfy the reviewed two-peer contract"
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
network_dns
network_dns_records
projects_networks_zones
network_acl
network_bridge_acl
firewall_driver
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

verify_firewall_backend()
{
  firewall_driver="$(printf '%s' "$server_metadata" |
    jq -er '.environment.firewall')" ||
    fail "the Incus API did not report its firewall driver"
  [ "$firewall_driver" = "nftables" ] ||
    fail "the Incus substrate requires the nftables firewall driver for bridge ACLs"
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
    --arg image "$instance_image" \
    --argjson ssh_test_enabled "$ssh_test_enabled" \
    --argjson ssh_test_acl_retained "$ssh_test_acl_retained" '{
      deployment_profile: $profile,
      incus_config_dir: $config_dir,
      incus_remote: $remote,
      platform_ipv4_cidr: $ipv4_cidr,
      platform_dns_domain: $dns_domain,
      instance_image: $image,
      ssh_test_enabled: $ssh_test_enabled,
      ssh_test_acl_retained: $ssh_test_acl_retained
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
  session_ssh_test_enabled="$(jq -er '.ssh_test_enabled | if type == "boolean" then tostring else empty end' "$session_file")" ||
    fail "planned Incus session has no SSH test fixture setting"
  session_ssh_test_acl_retained="$(jq -er '.ssh_test_acl_retained | if type == "boolean" then tostring else empty end' "$session_file")" ||
    fail "planned Incus session has no SSH ACL retirement setting"
  session_private_dns_secrets_file="$(jq -er '.private_dns_secrets_file' "$session_file")" ||
    fail "planned Incus session is invalid"
  expected_private_dns_secrets_sha="$(jq -er '.private_dns_secrets_sha256' "$session_file")" ||
    fail "planned Incus session has no private-DNS secret digest"
  expected_runtime_sha="$(jq -er '.runtime_vars_sha256' "$session_file")" ||
    fail "planned Incus session has no runtime-input digest"

  [ "$profile" = "$session_profile" ] ||
    fail "PROFILE does not match the reviewed Incus plan"
  [ "$remote" = "$session_remote" ] ||
    fail "INCUS_REMOTE does not match the reviewed Incus plan"
  [ "$endpoint" = "$session_endpoint" ] ||
    fail "INCUS_ENDPOINT does not match the reviewed Incus plan"
  [ "$ssh_test_enabled" = "$session_ssh_test_enabled" ] ||
    fail "SSH_TEST_ENABLED does not match the reviewed Incus plan"
  [ "$ssh_test_acl_retained" = "$session_ssh_test_acl_retained" ] ||
    fail "SSH_TEST_ACL_RETAINED does not match the reviewed Incus plan"
  [ "$normalized_expected" = "$session_fingerprint" ] ||
    fail "the server fingerprint does not match the reviewed Incus plan"
  [ "$private_dns_secrets_file" = "$session_private_dns_secrets_file" ] ||
    fail "PRIVATE_DNS_SECRETS_FILE does not match the reviewed Incus plan"
  actual_private_dns_secrets_sha="$(shasum -a 256 "$private_dns_secrets_file" | awk '{print $1}')"
  [ "$actual_private_dns_secrets_sha" = "$expected_private_dns_secrets_sha" ] ||
    fail "private DNS secrets changed after review; run make plan again"
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
  verify_firewall_backend
  validate_private_dns_secrets
  write_runtime_vars

  tofu -chdir="$terraform_root" plan \
    -input=false \
    -state="$state_file" \
    -var-file="$runtime_vars" \
    -var-file="$private_dns_secrets_file" \
    -out="$create_plan"
  plan_json="$(tofu -chdir="$terraform_root" show -json "$create_plan")"
  destructive_count="$(printf '%s' "$plan_json" | jq '[
    .resource_changes[]?
    | select(.mode == "managed")
    | select(.change.actions | index("delete"))
  ] | length')"
  if [ "$destructive_count" -ne 0 ] || [ "${RETIRE_SSH_TEST:-}" = "1" ]; then
    [ "${RETIRE_SSH_TEST:-}" = "1" ] && [ "$ssh_test_enabled" = "false" ] ||
      fail "the create plan contains destructive actions; use the replacement or destroy workflow"
    printf '%s' "$plan_json" | jq -e '
      [.resource_changes[]? | select(.mode == "managed") |
        select(.change.actions != ["no-op"]) |
        {address, actions: .change.actions,
         before_config: .change.before.config,
         after_config: .change.after.config}] as $changes
      | ($changes | length) > 0
      and (([$changes[] | select(.address == "incus_network_acl.ssh_test[0]")] | length) == 0
        or ([$changes[] | select(.address == "incus_network.platform")] | length) == 0)
      and all($changes[];
        (.address == "incus_network.platform" and .actions == ["update"]
         and .after_config["security.acls"] == "openbao-api,postgresql-tls"
         and .before_config["security.acls"] == "openbao-api,postgresql-tls,ssh-certificate-test"
         and (.before_config | del(."security.acls")) == (.after_config | del(."security.acls")))
        or (.address == "incus_instance.ssh_test[0]" and .actions == ["delete"])
        or (.address == "incus_profile.ssh_test[0]" and .actions == ["delete"])
        or (.address == "incus_network_acl.ssh_test[0]" and .actions == ["delete"])
      )
    ' >/dev/null || fail "retirement plan exceeds the disposable SSH target boundary"
  fi
  action_summary="$(printf '%s' "$plan_json" | jq -c '[
    .resource_changes[]?
    | select(.mode == "managed")
    | {address, actions: .change.actions}
  ]')"
  plan_sha="$(shasum -a 256 "$create_plan" | awk '{print $1}')"
  runtime_sha="$(shasum -a 256 "$runtime_vars" | awk '{print $1}')"
  private_dns_secrets_sha="$(shasum -a 256 "$private_dns_secrets_file" | awk '{print $1}')"
  jq -n \
    --arg profile "$profile" \
    --arg remote "$remote" \
    --arg endpoint "$endpoint" \
    --arg fingerprint "$normalized_expected" \
    --arg ipv4_cidr "$platform_ipv4_cidr" \
    --arg dns_domain "$platform_dns_domain" \
    --arg image "$instance_image" \
    --argjson ssh_test_enabled "$ssh_test_enabled" \
    --argjson ssh_test_acl_retained "$ssh_test_acl_retained" \
    --arg private_dns_secrets_file "$private_dns_secrets_file" \
    --arg private_dns_secrets_sha "$private_dns_secrets_sha" \
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
      ssh_test_enabled: $ssh_test_enabled,
      ssh_test_acl_retained: $ssh_test_acl_retained,
      private_dns_secrets_file: $private_dns_secrets_file,
      private_dns_secrets_sha256: $private_dns_secrets_sha,
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
    instances: [
      {
        name: .substrate.value.instance,
        type: .substrate.value.instance_type,
        ipv4_address: .substrate.value.instance_ipv4,
        dns_name: .substrate.value.instance_dns_name,
        status: .substrate.value.instance_status
      },
      {
        name: .openbao_foundation.value.instance,
        type: .openbao_foundation.value.instance_type,
        ipv4_address: .openbao_foundation.value.ipv4_address,
        dns_name: .openbao_foundation.value.dns_name,
        status: .openbao_foundation.value.status
      },
      {
        name: .postgresql_service.value.instance,
        type: .postgresql_service.value.instance_type,
        ipv4_address: .postgresql_service.value.ipv4_address,
        dns_name: .postgresql_service.value.dns_name,
        status: .postgresql_service.value.status
      }
    ] + (if .ssh_test_service.value == null then [] else [{
      name: .ssh_test_service.value.instance,
      type: .ssh_test_service.value.instance_type,
      ipv4_address: .ssh_test_service.value.ipv4_address,
      dns_name: .ssh_test_service.value.dns_name,
      status: .ssh_test_service.value.status
    }] end)
  }' >"$inventory_file"
  printf '%s' "$outputs" | jq \
    --arg remote "$remote" \
    --arg profile "$profile" \
    --arg client_cidr "$platform_ipv4_cidr" \
    --arg project "$(printf '%s' "$outputs" | jq -r '.substrate.value.project')" '{
      all: {
        children: {
          dns_secondaries: {
            vars: {
              ansible_connection: "community.general.incus",
              ansible_incus_remote: $remote,
              ansible_incus_project: $project,
              ansible_user: "root",
              rpr_deployment_profile: $profile,
              bind_secondary_primary_address: .private_dns.value.primary_address,
              bind_secondary_primary_port: .private_dns.value.primary_port,
              bind_secondary_client_cidr: $client_cidr,
              bind_secondary_forward_zone: .private_dns.value.forward_zone,
              bind_secondary_reverse_zone: .private_dns.value.reverse_zone,
              bind_secondary_expected_automatic_name: .substrate.value.instance_dns_name,
              bind_secondary_expected_automatic_ipv4: .substrate.value.instance_ipv4,
              bind_secondary_expected_manual_name: .private_dns.value.resolver_name,
              bind_secondary_expected_manual_ipv4_addresses:
                ([.private_dns.value.secondaries[].ipv4_address] | sort)
            },
            hosts: (.private_dns.value.secondaries | with_entries({
              key: .key,
              value: {
                ansible_host: .key,
                bind_secondary_listen_address: .value.ipv4_address,
                bind_secondary_peer_name: .key,
                bind_secondary_forward_tsig_secret: ("{{ private_dns_tsig_secrets[\"" + .key + "\"].forward }}"),
                bind_secondary_reverse_tsig_secret: ("{{ private_dns_tsig_secrets[\"" + .key + "\"].reverse }}")
              }
            }))
          }
        }
      }
    }' >"$private_dns_inventory_file"
  printf '%s' "$outputs" | jq \
    --arg remote "$remote" \
    --arg profile "$profile" \
    --arg client_cidr "$platform_ipv4_cidr" \
    --arg project "$(printf '%s' "$outputs" | jq -r '.substrate.value.project')" '{
      all: {
        children: {
          openbao_service: {
            vars: {
              ansible_connection: "community.general.incus",
              ansible_incus_remote: $remote,
              ansible_incus_project: $project,
              ansible_user: "root",
              rpr_deployment_profile: $profile,
              openbao_platform_cidr: $client_cidr,
              openbao_api_address: .openbao_foundation.value.ipv4_address,
              openbao_api_port: .openbao_foundation.value.api_port,
              openbao_api_dns_name: .openbao_foundation.value.alias_name
            },
            hosts: {
              (.openbao_foundation.value.instance): {
                ansible_host: .openbao_foundation.value.instance
              }
            }
          },
          machine_auth_client: {
            vars: {
              ansible_connection: "community.general.incus",
              ansible_incus_remote: $remote,
              ansible_incus_project: $project,
              ansible_user: "root",
              rpr_deployment_profile: $profile
            },
            hosts: {
              (.substrate.value.instance): {
                ansible_host: .substrate.value.instance
              }
            }
          },
          postgresql_service: {
            vars: {
              ansible_connection: "community.general.incus",
              ansible_incus_remote: $remote,
              ansible_incus_project: $project,
              ansible_user: "root",
              rpr_deployment_profile: $profile,
              postgresql_private_address: .postgresql_service.value.ipv4_address,
              postgresql_private_dns_name: .postgresql_service.value.dns_name,
              postgresql_listen_port: .postgresql_service.value.port,
              postgresql_client_address: .substrate.value.instance_ipv4,
              postgresql_openbao_address: .openbao_foundation.value.ipv4_address
            },
            hosts: {
              (.postgresql_service.value.instance): {
                ansible_host: .postgresql_service.value.instance
              }
            }
          },
          ssh_test_target: (if .ssh_test_service.value == null then null else {
            vars: {
              ansible_connection: "community.general.incus",
              ansible_incus_remote: $remote,
              ansible_incus_project: $project,
              ansible_user: "root",
              rpr_deployment_profile: $profile,
              ssh_test_private_address: .ssh_test_service.value.ipv4_address,
              ssh_test_private_dns_name: .ssh_test_service.value.dns_name,
              ssh_test_client_address: .substrate.value.instance_ipv4
            },
            hosts: {
              (.ssh_test_service.value.instance): {
                ansible_host: .ssh_test_service.value.instance
              }
            }
          } end)
        }
      }
    } | if .all.children.ssh_test_target == null
        then del(.all.children.ssh_test_target) else . end' >"$openbao_inventory_file"
}

apply_plan()
{
  expected="apply-incus-$profile-$remote"
  [ "${CONFIRM:-}" = "$expected" ] ||
    fail "set CONFIRM=$expected to create the Incus substrate"
  for tool in jq shasum tofu; do
    require_tool "$tool"
  done
  validate_private_dns_secrets
  load_session
  verify_create_plan
  verify_client_trust
  verify_server_capabilities
  verify_firewall_backend

  umask 077
  echo "Applying only the reviewed Incus plan to $remote ($endpoint)."
  tofu -chdir="$terraform_root" apply \
    -input=false \
    -state="$state_file" \
    "$create_plan"
  write_inventory
  rm -f "$create_plan"
  echo "Generated ignored inventory: $inventory_file"
  echo "Generated ignored private DNS inventory: $private_dns_inventory_file"
  echo "Generated ignored OpenBao inventory: $openbao_inventory_file"
  echo "Run make validate, then make plan again to prove no drift."
}

validate_substrate()
{
  for tool in incus jq tofu; do
    require_tool "$tool"
  done
  validate_private_dns_secrets
  load_session
  verify_client_trust
  verify_server_capabilities
  verify_firewall_backend
  [ -r "$state_file" ] || fail "Incus state is missing; run make apply first"

  outputs="$(tofu -chdir="$terraform_root" output -state="$state_file" -json)"
  project_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.project')"
  pool_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.storage_pool')"
  network_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.network')"
  profile_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.profile')"
  instance_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.instance')"
  instance_dns_name="$(printf '%s' "$outputs" | jq -er '.substrate.value.instance_dns_name')"
  bridge_ipv4_address="$(printf '%s' "$outputs" | jq -er '.substrate.value.bridge_ipv4_address')"
  dns_profile_name="$(printf '%s' "$outputs" | jq -er '.private_dns.value.profile')"
  forward_zone="$(printf '%s' "$outputs" | jq -er '.private_dns.value.forward_zone')"
  reverse_zone="$(printf '%s' "$outputs" | jq -er '.private_dns.value.reverse_zone')"
  openbao_profile_name="$(printf '%s' "$outputs" | jq -er '.openbao_foundation.value.profile')"
  openbao_instance_name="$(printf '%s' "$outputs" | jq -er '.openbao_foundation.value.instance')"
  openbao_ipv4_address="$(printf '%s' "$outputs" | jq -er '.openbao_foundation.value.ipv4_address')"
  openbao_dns_name="$(printf '%s' "$outputs" | jq -er '.openbao_foundation.value.dns_name')"
  openbao_alias_name="$(printf '%s' "$outputs" | jq -er '.openbao_foundation.value.alias_name')"
  openbao_api_port="$(printf '%s' "$outputs" | jq -er '.openbao_foundation.value.api_port')"
  openbao_acl_name="$(printf '%s' "$outputs" | jq -er '.openbao_foundation.value.network_acl')"
  postgresql_profile_name="$(printf '%s' "$outputs" | jq -er '.postgresql_service.value.profile')"
  postgresql_instance_name="$(printf '%s' "$outputs" | jq -er '.postgresql_service.value.instance')"
  postgresql_ipv4_address="$(printf '%s' "$outputs" | jq -er '.postgresql_service.value.ipv4_address')"
  postgresql_dns_name="$(printf '%s' "$outputs" | jq -er '.postgresql_service.value.dns_name')"
  postgresql_port="$(printf '%s' "$outputs" | jq -er '.postgresql_service.value.port')"
  postgresql_acl_name="$(printf '%s' "$outputs" | jq -er '.postgresql_service.value.network_acl')"
  ssh_test_present="$(printf '%s' "$outputs" | jq -r '.ssh_test_service.value != null')"
  [ "$ssh_test_present" = "$ssh_test_enabled" ] ||
    fail "SSH test target state differs from the reviewed Incus session"
  if [ "$ssh_test_present" = "true" ]; then
    ssh_test_profile_name="$(printf '%s' "$outputs" | jq -er '.ssh_test_service.value.profile')"
    ssh_test_instance_name="$(printf '%s' "$outputs" | jq -er '.ssh_test_service.value.instance')"
    ssh_test_ipv4_address="$(printf '%s' "$outputs" | jq -er '.ssh_test_service.value.ipv4_address')"
    ssh_test_dns_name="$(printf '%s' "$outputs" | jq -er '.ssh_test_service.value.dns_name')"
    ssh_test_port="$(printf '%s' "$outputs" | jq -er '.ssh_test_service.value.port')"
    ssh_test_acl_name="$(printf '%s' "$outputs" | jq -er '.ssh_test_service.value.network_acl')"
    expected_ssh_test_answer="$ssh_test_ipv4_address"
  else
    ssh_test_dns_name="ssh-test-01.${session_dns_domain}"
    expected_ssh_test_answer=""
  fi
  planned_image="$(printf '%s' "$outputs" | jq -er '.substrate.value.instance_image')"
  [ "$planned_image" = "$session_image" ] ||
    fail "the state image differs from the reviewed Incus session"

  project_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/projects/${project_name}")"
  [ "$(printf '%s' "$project_json" | jq -r '.config.restricted')" = "true" ] ||
    fail "the Incus project is not restricted"
  [ "$(printf '%s' "$project_json" | jq -r '.config["limits.containers"]')" = "6" ] ||
    fail "the Incus project does not enforce the six-container limit"
  [ "$(printf '%s' "$project_json" | jq -r '.config["limits.instances"]')" = "6" ] ||
    fail "the Incus project does not enforce the six-instance limit"
  [ "$(printf '%s' "$project_json" | jq -r '.config["limits.cpu"]')" = "6" ] ||
    fail "the Incus project aggregate CPU limit differs from the active boundary"
  [ "$(printf '%s' "$project_json" | jq -r '.config["limits.memory"]')" = "2304MiB" ] ||
    fail "the Incus project aggregate memory limit differs from the active boundary"
  [ "$(printf '%s' "$project_json" | jq -r '.config["limits.virtual-machines"]')" = "0" ] ||
    fail "the Incus project permits virtual machines"
  [ "$(printf '%s' "$project_json" | jq -r '.config["restricted.networks.access"]')" = "$network_name" ] ||
    fail "the Incus project permits an unexpected managed network"
  [ "$(printf '%s' "$project_json" | jq -r '.config["features.networks.zones"]')" = "true" ] ||
    fail "the Incus project does not isolate its network zones"
  [ "$(printf '%s' "$project_json" | jq -r '.config["restricted.networks.zones"]')" = "${session_dns_domain},${reverse_zone}" ] ||
    fail "the Incus project permits unexpected network zones"
  [ "$(printf '%s' "$project_json" | jq -r '.config["limits.disk"]')" = "18GiB" ] ||
    fail "the Incus project aggregate disk limit differs from the active boundary"
  [ "$(printf '%s' "$project_json" |
    jq -r --arg key "limits.disk.pool.${pool_name}" '.config[$key]')" = "18GiB" ] ||
    fail "the Incus project per-pool disk limit differs from the active boundary"

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
  [ "$(printf '%s' "$network_json" | jq -r '.config["dns.zone.forward"]')" = "$forward_zone" ] ||
    fail "the managed bridge is not attached to the private forward zone"
  [ "$(printf '%s' "$network_json" | jq -r '.config["dns.zone.reverse.ipv4"]')" = "$reverse_zone" ] ||
    fail "the managed bridge is not attached to the private reverse zone"
  expected_acls="${openbao_acl_name},${postgresql_acl_name}"
  if [ "$ssh_test_present" = "true" ]; then
    expected_acls="${expected_acls},${ssh_test_acl_name}"
  fi
  [ "$(printf '%s' "$network_json" | jq -r '.config["security.acls"]')" = "$expected_acls" ] ||
    fail "the managed bridge is not attached to all service ACLs"
  [ "$(printf '%s' "$network_json" | jq -r '.config["security.acls.default.ingress.action"]')" = "allow" ] ||
    fail "the managed bridge does not preserve ingress for ordinary NICs"
  [ "$(printf '%s' "$network_json" | jq -r '.config["security.acls.default.egress.action"]')" = "allow" ] ||
    fail "the managed bridge does not preserve egress for ordinary NICs"

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

  dns_profile_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/profiles/${dns_profile_name}?project=${project_name}")"
  [ "$(printf '%s' "$dns_profile_json" | jq -r '.config["security.privileged"]')" = "false" ] ||
    fail "the DNS profile does not enforce unprivileged containers"
  [ "$(printf '%s' "$dns_profile_json" | jq -r '.config["limits.memory"]')" = "256MiB" ] ||
    fail "the DNS profile memory limit differs from the reviewed boundary"
  [ "$(printf '%s' "$dns_profile_json" | jq -r '.devices.root.size')" = "2GiB" ] ||
    fail "the DNS profile disk limit differs from the reviewed boundary"

  openbao_profile_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/profiles/${openbao_profile_name}?project=${project_name}")"
  [ "$(printf '%s' "$openbao_profile_json" | jq -r '.config["limits.cpu"]')" = "1" ] ||
    fail "the OpenBao profile CPU limit differs from the reviewed boundary"
  [ "$(printf '%s' "$openbao_profile_json" | jq -r '.config["limits.memory"]')" = "512MiB" ] ||
    fail "the OpenBao profile memory limit differs from the reviewed boundary"
  [ "$(printf '%s' "$openbao_profile_json" | jq -r '.config["security.nesting"]')" = "false" ] ||
    fail "the OpenBao profile permits container nesting"
  [ "$(printf '%s' "$openbao_profile_json" | jq -r '.config["security.privileged"]')" = "false" ] ||
    fail "the OpenBao profile does not enforce an unprivileged container"
  [ "$(printf '%s' "$openbao_profile_json" | jq -r '.devices.root.pool')" = "$pool_name" ] ||
    fail "the OpenBao profile root disk uses the wrong pool"
  [ "$(printf '%s' "$openbao_profile_json" | jq -r '.devices.root.size')" = "4GiB" ] ||
    fail "the OpenBao profile disk limit differs from the reviewed boundary"

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

  for dns_name in dns-01 dns-02; do
    expected_dns_ipv4="$(printf '%s' "$outputs" |
      jq -er --arg name "$dns_name" '.private_dns.value.secondaries[$name].ipv4_address')"
    dns_state_json="$(INCUS_CONF="$config_dir" incus query \
      "${remote}:/1.0/instances/${dns_name}/state?project=${project_name}")"
    [ "$(printf '%s' "$dns_state_json" | jq -r '.status')" = "Running" ] ||
      fail "$dns_name is not running"
    actual_dns_ipv4="$(printf '%s' "$dns_state_json" | jq -er '
      [.network.eth0.addresses[]
        | select(.family == "inet" and .scope == "global")
        | .address][0]
    ')" || fail "$dns_name has no global IPv4 address on eth0"
    [ "$actual_dns_ipv4" = "$expected_dns_ipv4" ] ||
      fail "$dns_name does not use its reviewed static address"
  done

  openbao_acl_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/network-acls/${openbao_acl_name}?project=default")"
  printf '%s' "$openbao_acl_json" | jq -e \
    --arg source "$session_ipv4_cidr" \
    --arg destination "$openbao_ipv4_address" \
    --arg port "$openbao_api_port" '
      (.ingress | length) == 1
      and (.egress | length) == 0
      and .ingress[0].action == "allow"
      and .ingress[0].source == $source
      and .ingress[0].destination == $destination
      and .ingress[0].destination_port == $port
      and .ingress[0].protocol == "tcp"
      and .ingress[0].state == "enabled"
    ' >/dev/null || fail "the OpenBao network ACL differs from the reviewed boundary"

  openbao_instance_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/instances/${openbao_instance_name}?project=${project_name}")"
  [ "$(printf '%s' "$openbao_instance_json" | jq -r '.type')" = "container" ] ||
    fail "the OpenBao instance is not a system container"
  [ "$(printf '%s' "$openbao_instance_json" | jq -r '.devices.eth0.network')" = "$network_name" ] ||
    fail "the OpenBao instance NIC uses the wrong network"
  [ "$(printf '%s' "$openbao_instance_json" | jq -r '.devices.eth0["ipv4.address"]')" = "$openbao_ipv4_address" ] ||
    fail "the OpenBao instance NIC does not use its reviewed static address"
  [ "$(printf '%s' "$openbao_instance_json" | jq -r '.devices.eth0["security.acls.default.ingress.action"]')" = "reject" ] ||
    fail "the OpenBao instance NIC does not reject unmatched ingress"
  [ "$(printf '%s' "$openbao_instance_json" | jq -r '.devices.eth0["security.acls.default.egress.action"]')" = "allow" ] ||
    fail "the OpenBao instance NIC does not explicitly allow egress"

  openbao_state_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/instances/${openbao_instance_name}/state?project=${project_name}")"
  [ "$(printf '%s' "$openbao_state_json" | jq -r '.status')" = "Running" ] ||
    fail "the OpenBao container is not running"
  actual_openbao_ipv4="$(printf '%s' "$openbao_state_json" | jq -er '
    [.network.eth0.addresses[]
      | select(.family == "inet" and .scope == "global")
      | .address][0]
  ')" || fail "the OpenBao container has no global IPv4 address on eth0"
  [ "$actual_openbao_ipv4" = "$openbao_ipv4_address" ] ||
    fail "the OpenBao container does not use its reviewed static address"

  postgresql_profile_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/profiles/${postgresql_profile_name}?project=${project_name}")"
  printf '%s' "$postgresql_profile_json" | jq -e --arg pool "$pool_name" '
    .config["limits.cpu"] == "1"
    and .config["limits.memory"] == "512MiB"
    and .config["security.nesting"] == "false"
    and .config["security.privileged"] == "false"
    and .devices.root.pool == $pool
    and .devices.root.size == "4GiB"
  ' >/dev/null || fail "the PostgreSQL profile differs from the reviewed boundary"

  postgresql_acl_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/network-acls/${postgresql_acl_name}?project=default")"
  printf '%s' "$postgresql_acl_json" | jq -e \
    --arg source "$session_ipv4_cidr" \
    --arg destination "$postgresql_ipv4_address" \
    --arg port "$postgresql_port" '
      (.ingress | length) == 1
      and (.egress | length) == 0
      and .ingress[0].action == "allow"
      and .ingress[0].source == $source
      and .ingress[0].destination == $destination
      and .ingress[0].destination_port == $port
      and .ingress[0].protocol == "tcp"
      and .ingress[0].state == "enabled"
    ' >/dev/null || fail "the PostgreSQL NIC ACL differs from the reviewed boundary"

  postgresql_instance_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/instances/${postgresql_instance_name}?project=${project_name}")"
  printf '%s' "$postgresql_instance_json" | jq -e \
    --arg network "$network_name" \
    --arg address "$postgresql_ipv4_address" '
      .type == "container"
      and .devices.eth0.network == $network
      and .devices.eth0["ipv4.address"] == $address
      and .devices.eth0["security.acls.default.ingress.action"] == "reject"
      and .devices.eth0["security.acls.default.egress.action"] == "allow"
    ' >/dev/null || fail "the PostgreSQL instance NIC differs from the reviewed boundary"
  postgresql_state_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/instances/${postgresql_instance_name}/state?project=${project_name}")"
  [ "$(printf '%s' "$postgresql_state_json" | jq -r '.status')" = "Running" ] ||
    fail "the PostgreSQL container is not running"
  actual_postgresql_ipv4="$(printf '%s' "$postgresql_state_json" | jq -er '
    [.network.eth0.addresses[]
      | select(.family == "inet" and .scope == "global")
      | .address][0]
  ')" || fail "the PostgreSQL container has no global IPv4 address on eth0"
  [ "$actual_postgresql_ipv4" = "$postgresql_ipv4_address" ] ||
    fail "the PostgreSQL container does not use its reviewed static address"

  if [ "$ssh_test_present" = "true" ]; then
  ssh_test_profile_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/profiles/${ssh_test_profile_name}?project=${project_name}")"
  printf '%s' "$ssh_test_profile_json" | jq -e --arg pool "$pool_name" '
    .config["limits.cpu"] == "1"
    and .config["limits.memory"] == "256MiB"
    and .config["security.nesting"] == "false"
    and .config["security.privileged"] == "false"
    and .devices.root.pool == $pool
    and .devices.root.size == "2GiB"
  ' >/dev/null || fail "the SSH test profile differs from the reviewed boundary"

  ssh_test_acl_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/network-acls/${ssh_test_acl_name}?project=default")"
  printf '%s' "$ssh_test_acl_json" | jq -e \
    --arg source "$session_ipv4_cidr" \
    --arg destination "$ssh_test_ipv4_address" \
    --arg port "$ssh_test_port" '
      (.ingress | length) == 1
      and (.egress | length) == 0
      and .ingress[0].action == "allow"
      and .ingress[0].source == $source
      and .ingress[0].destination == $destination
      and .ingress[0].destination_port == $port
      and .ingress[0].protocol == "tcp"
      and .ingress[0].state == "enabled"
    ' >/dev/null || fail "the SSH test network ACL differs from the reviewed boundary"

  ssh_test_instance_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/instances/${ssh_test_instance_name}?project=${project_name}")"
  printf '%s' "$ssh_test_instance_json" | jq -e \
    --arg network "$network_name" \
    --arg address "$ssh_test_ipv4_address" '
      .type == "container"
      and .devices.eth0.network == $network
      and .devices.eth0["ipv4.address"] == $address
      and .devices.eth0["security.acls.default.ingress.action"] == "reject"
      and .devices.eth0["security.acls.default.egress.action"] == "allow"
    ' >/dev/null || fail "the SSH test instance NIC differs from the reviewed boundary"
  ssh_test_state_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/instances/${ssh_test_instance_name}/state?project=${project_name}")"
  [ "$(printf '%s' "$ssh_test_state_json" | jq -r '.status')" = "Running" ] ||
    fail "the SSH test container is not running"
  actual_ssh_test_ipv4="$(printf '%s' "$ssh_test_state_json" | jq -er '
    [.network.eth0.addresses[]
      | select(.family == "inet" and .scope == "global")
      | .address][0]
  ')" || fail "the SSH test container has no global IPv4 address on eth0"
  [ "$actual_ssh_test_ipv4" = "$ssh_test_ipv4_address" ] ||
    fail "the SSH test container does not use its reviewed static address"
  fi

  forward_zone_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/network-zones/${forward_zone}?project=${project_name}")"
  reverse_zone_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/network-zones/${reverse_zone}?project=${project_name}")"
  for dns_name in dns-01 dns-02; do
    expected_dns_ipv4="$(printf '%s' "$outputs" |
      jq -er --arg name "$dns_name" '.private_dns.value.secondaries[$name].ipv4_address')"
    [ "$(printf '%s' "$forward_zone_json" |
      jq -r --arg key "peers.${dns_name}.address" '.config[$key]')" = "$expected_dns_ipv4" ] ||
      fail "the forward zone has an unexpected $dns_name peer address"
    [ "$(printf '%s' "$reverse_zone_json" |
      jq -r --arg key "peers.${dns_name}.address" '.config[$key]')" = "$expected_dns_ipv4" ] ||
      fail "the reverse zone has an unexpected $dns_name peer address"
    printf '%s' "$forward_zone_json" |
      jq -e --arg key "peers.${dns_name}.key" '.config[$key] | length >= 32' >/dev/null ||
      fail "the forward zone has no protected $dns_name transfer key"
    printf '%s' "$reverse_zone_json" |
      jq -e --arg key "peers.${dns_name}.key" '.config[$key] | length >= 32' >/dev/null ||
      fail "the reverse zone has no protected $dns_name transfer key"
  done

  resolver_record_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/network-zones/${forward_zone}/records/resolver?project=${project_name}")"
  [ "$(printf '%s' "$resolver_record_json" | jq '[.entries[] | select(.type == "A")] | length')" = "2" ] ||
    fail "the provider-owned resolver record does not contain two A entries"
  openbao_record_json="$(INCUS_CONF="$config_dir" incus query \
    "${remote}:/1.0/network-zones/${forward_zone}/records/openbao?project=${project_name}")"
  printf '%s' "$openbao_record_json" | jq -e --arg target "${openbao_dns_name}." '
    (.entries | length) == 1
    and .entries[0].type == "CNAME"
    and .entries[0].value == $target
  ' >/dev/null || fail "the private OpenBao alias differs from the reviewed target"
  for dns_name in dns-01 dns-02; do
    expected_dns_ipv4="$(printf '%s' "$outputs" |
      jq -er --arg name "$dns_name" '.private_dns.value.secondaries[$name].ipv4_address')"
    INCUS_CONF="$config_dir" incus exec --project "$project_name" \
      "${remote}:${dns_name}" -- rndc refresh "$forward_zone" >/dev/null
    attempt=0
    while [ "$attempt" -lt 30 ]; do
      alias_answer="$(INCUS_CONF="$config_dir" incus exec --project "$project_name" \
        "${remote}:${dns_name}" -- dig "@${expected_dns_ipv4}" \
        "$openbao_alias_name" CNAME +norecurse +short 2>/dev/null || true)"
      address_answer="$(INCUS_CONF="$config_dir" incus exec --project "$project_name" \
        "${remote}:${dns_name}" -- dig "@${expected_dns_ipv4}" \
        "$openbao_dns_name" A +norecurse +short 2>/dev/null || true)"
      postgresql_answer="$(INCUS_CONF="$config_dir" incus exec --project "$project_name" \
        "${remote}:${dns_name}" -- dig "@${expected_dns_ipv4}" \
        "$postgresql_dns_name" A +norecurse +short 2>/dev/null || true)"
      ssh_test_answer="$(INCUS_CONF="$config_dir" incus exec --project "$project_name" \
        "${remote}:${dns_name}" -- dig "@${expected_dns_ipv4}" \
        "$ssh_test_dns_name" A +norecurse +short 2>/dev/null || true)"
      if [ "$alias_answer" = "${openbao_dns_name}." ] &&
        [ "$address_answer" = "$openbao_ipv4_address" ] &&
        [ "$postgresql_answer" = "$postgresql_ipv4_address" ] &&
        [ "$ssh_test_answer" = "$expected_ssh_test_answer" ]; then
        break
      fi
      attempt=$((attempt + 1))
      sleep 1
    done
    [ "$attempt" -lt 30 ] ||
      fail "$dns_name did not serve the reviewed service names"
  done

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
    --arg forward_zone "$forward_zone" \
    --arg reverse_zone "$reverse_zone" \
    --argjson secondaries "$(printf '%s' "$outputs" | jq '.private_dns.value.secondaries')" \
    --argjson openbao "$(printf '%s' "$outputs" | jq '.openbao_foundation.value')" \
    --argjson postgresql "$(printf '%s' "$outputs" | jq '.postgresql_service.value')" \
    --argjson ssh_test "$(printf '%s' "$outputs" | jq '.ssh_test_service.value')" \
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
      private_dns_infrastructure_ready: true,
      private_dns_forward_zone: $forward_zone,
      private_dns_reverse_zone: $reverse_zone,
      private_dns_secondaries: $secondaries,
      openbao_foundation_ready: true,
      openbao: $openbao,
      postgresql_substrate_ready: true,
      postgresql: $postgresql,
      ssh_test_substrate_ready: ($ssh_test != null),
      ssh_test: $ssh_test,
      ipv6_policy: "disabled"
    }' >"$evidence_file"
  write_inventory

  echo "Incus substrate validation passed: $instance_name ($instance_ipv4), $openbao_instance_name ($actual_openbao_ipv4), $postgresql_instance_name ($actual_postgresql_ipv4), SSH target enabled=$ssh_test_present"
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
  validate_private_dns_secrets
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
    -var-file="$private_dns_secrets_file" \
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
  rm -f "$create_plan" "$destroy_plan" "$inventory_file" \
    "$private_dns_inventory_file" "$openbao_inventory_file" "$evidence_file"
  echo "Incus provider destroy finished; the Incus server remains installed and initialized."
}

require_profile
validate_inputs
case "$action" in
  preflight)
    verify_client_trust
    verify_server_capabilities
    verify_firewall_backend
    ;;
  plan) plan ;;
  apply) apply_plan ;;
  validate) validate_substrate ;;
  destroy) destroy ;;
  *) fail "usage: $0 {preflight|plan|apply|validate|destroy}" ;;
esac
