#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

action=${1:-}
profile=${PROFILE:-}
terraform_root="infrastructure/bootstrap/aws-single-node"
cache_dir=${RPR_AWS_CACHE_DIR:-"$PWD/.cache/aws-single-node"}
runtime_vars="$cache_dir/runtime.auto.tfvars.json"
session_file="$cache_dir/session.json"
create_plan="$cache_dir/create.tfplan"
destroy_plan="$cache_dir/destroy.tfplan"
inventory_file="$cache_dir/hosts.json"
project_tag="reliability-platform-reference"

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
  [ "$profile" = "single-node-reference" ] ||
    fail "set PROFILE=single-node-reference"
}

aws_call()
{
  call_region=$1
  shift
  AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off \
    aws --profile "$aws_profile" --region "$call_region" "$@" \
    --no-cli-pager
}

read_identity()
{
  identity=$(aws_call "$aws_region" sts get-caller-identity --output json)
  account_id=$(printf '%s' "$identity" | jq -er '.Account') ||
    fail "AWS caller identity did not contain an account ID"
  caller_arn=$(printf '%s' "$identity" | jq -er '.Arn') ||
    fail "AWS caller identity did not contain an ARN"

  case "$caller_arn" in
    arn:aws:iam::*:root) fail "refusing to run with AWS root credentials" ;;
  esac
}

load_session()
{
  [ -r "$session_file" ] ||
    fail "no planned AWS session exists; run make aws-plan first"
  [ -r "$runtime_vars" ] ||
    fail "planned runtime inputs are missing; run make aws-plan again"

  session_profile=$(jq -er '.aws_profile' "$session_file") ||
    fail "planned session is invalid"
  session_account_id=$(jq -er '.account_id' "$session_file") ||
    fail "planned session is invalid"
  aws_region=$(jq -er '.aws_region' "$session_file") ||
    fail "planned session is invalid"
  expires_at=$(jq -er '.expires_at' "$session_file") ||
    fail "planned session is invalid"

  aws_profile=${AWS_PROFILE:-}
  [ -n "$aws_profile" ] || fail "set AWS_PROFILE to the reviewed CLI profile"
  [ "$aws_profile" = "$session_profile" ] ||
    fail "AWS_PROFILE does not match the profile used by aws-plan"
}

require_live_session()
{
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  jq -en --arg now "$now" --arg expires "$expires_at" \
    '($expires | fromdateiso8601) > ($now | fromdateiso8601)' >/dev/null ||
    fail "the planned session expired at $expires_at; destroy or create a fresh plan"
}

verify_planned_identity()
{
  read_identity
  [ "$account_id" = "$session_account_id" ] ||
    fail "current AWS account does not match the planned account"
}

extract_rate()
{
  unit=$1
  jq -er --arg unit "$unit" '
    [
      .PriceList[]
      | fromjson
      | .terms.OnDemand[]?.priceDimensions[]?
      | select(.unit == $unit)
      | .pricePerUnit.USD
      | tonumber
      | select(. > 0)
    ]
    | if length == 0 then error("price not found") else min end
  '
}

timestamp_to_epoch()
{
  python3 - "$1" <<'PY'
from datetime import datetime
import sys

value = sys.argv[1]
try:
    print(int(float(value)))
except ValueError:
    print(int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()))
PY
}

plan()
{
  aws_profile=${AWS_PROFILE:-}
  budget_name=${AWS_BUDGET_NAME:-}
  owner=${OWNER:-}
  operator_cidr=${OPERATOR_CIDR:-}
  public_key_file=${OPERATOR_PUBLIC_KEY_FILE:-}
  ttl_hours=${TTL_HOURS:-}
  aws_region=${AWS_REGION:-eu-central-1}
  instance_type=${INSTANCE_TYPE:-t4g.small}
  root_volume_size=${ROOT_VOLUME_SIZE_GIB:-30}

  [ -n "$aws_profile" ] || fail "set AWS_PROFILE to a non-root CLI profile"
  [ -n "$budget_name" ] || fail "set AWS_BUDGET_NAME to an existing cost budget"
  [ -n "$owner" ] || fail "set OWNER to the human resource owner"
  [ -n "$operator_cidr" ] || fail "set OPERATOR_CIDR to your public IPv4 /32"
  case "$operator_cidr" in
    */32) ;;
    *) fail "OPERATOR_CIDR must be one public IPv4 /32" ;;
  esac
  [ -n "$public_key_file" ] ||
    fail "set OPERATOR_PUBLIC_KEY_FILE to a dedicated public key"
  [ -r "$public_key_file" ] ||
    fail "public key is not readable: $public_key_file"
  [ -n "$ttl_hours" ] || fail "set TTL_HOURS to an integer from 1 through 12"
  case "$ttl_hours" in
    *[!0-9]*|'') fail "TTL_HOURS must be an integer from 1 through 12" ;;
  esac
  [ "$ttl_hours" -ge 1 ] && [ "$ttl_hours" -le 12 ] ||
    fail "TTL_HOURS must be an integer from 1 through 12"
  case "$root_volume_size" in
    *[!0-9]*|'') fail "ROOT_VOLUME_SIZE_GIB must be an integer" ;;
  esac

  case "$aws_region" in
    eu-central-1)
      pricing_location="EU (Frankfurt)"
      pricing_ipv4_usage="EUC1-PublicIPv4:InUseAddress"
      ;;
    *) fail "P1-04 currently supports AWS_REGION=eu-central-1 only" ;;
  esac
  billing_region="us-east-1"

  for tool in aws jq python3 ssh-keygen tofu; do
    require_tool "$tool"
  done
  [ -d "$terraform_root/.terraform" ] ||
    fail "run make setup-hcl before planning AWS resources"
  ssh-keygen -l -f "$public_key_file" >/dev/null 2>&1 ||
    fail "OPERATOR_PUBLIC_KEY_FILE is not a valid OpenSSH public key"

  read_identity

  if free_tier=$(aws_call "$billing_region" freetier \
    get-account-plan-state --output json 2>&1); then
    free_tier_account=$(printf '%s' "$free_tier" | jq -er '.accountId') ||
      fail "could not read the AWS account plan state"
    [ "$free_tier_account" = "$account_id" ] ||
      fail "Free Tier status belongs to a different AWS account"
    free_tier_summary=$(printf '%s' "$free_tier" | jq -c '{
      type: .accountPlanType,
      status: .accountPlanStatus,
      expires: .accountPlanExpirationDate,
      credits: .accountPlanRemainingCredits,
      discount_assumption: "eligibility-only"
    }')
  else
    case "$free_tier" in
      *ResourceNotFoundException*)
        free_tier_summary='{"type":"unavailable","status":"NO_ACCOUNT_PLAN_RECORD","discount_assumption":"none"}'
        ;;
      *)
        printf '%s\n' "$free_tier" >&2
        fail "could not query the AWS account plan state"
        ;;
    esac
  fi

  budget=$(aws_call "$billing_region" budgets describe-budget \
    --account-id "$account_id" --budget-name "$budget_name" --output json)
  [ "$(printf '%s' "$budget" | jq -er '.Budget.BudgetType')" = "COST" ] ||
    fail "AWS_BUDGET_NAME must identify a COST budget"
  budget_start=$(printf '%s' "$budget" |
    jq -er '.Budget.TimePeriod.Start | tostring') ||
    fail "the selected AWS budget has no start time"
  budget_end=$(printf '%s' "$budget" |
    jq -er '.Budget.TimePeriod.End | tostring') ||
    fail "the selected AWS budget has no end time"
  budget_start_epoch=$(timestamp_to_epoch "$budget_start" 2>/dev/null) ||
    fail "could not parse the selected AWS budget start time"
  budget_end_epoch=$(timestamp_to_epoch "$budget_end" 2>/dev/null) ||
    fail "could not parse the selected AWS budget end time"
  now_epoch=$(date -u +%s)
  [ "$budget_start_epoch" -le "$now_epoch" ] &&
    [ "$budget_end_epoch" -gt "$now_epoch" ] ||
    fail "the selected AWS budget is not active"
  budget_limit=$(printf '%s' "$budget" |
    jq -er '.Budget.BudgetLimit | "\(.Amount) \(.Unit)"') ||
    fail "the selected budget has no fixed budget limit"

  notifications=$(aws_call "$billing_region" budgets describe-notifications-for-budget \
    --account-id "$account_id" --budget-name "$budget_name" --output json)
  notification_count=$(printf '%s' "$notifications" |
    jq -er '.Notifications | length') || fail "could not inspect budget alerts"
  [ "$notification_count" -gt 0 ] ||
    fail "the selected AWS budget has no notification"

  subscriber_count=0
  notification_index=0
  while [ "$notification_index" -lt "$notification_count" ]; do
    notification=$(printf '%s' "$notifications" | jq -c \
      ".Notifications[$notification_index] | {
        NotificationType,
        ComparisonOperator,
        Threshold,
        ThresholdType: (.ThresholdType // \"PERCENTAGE\")
      }")
    subscribers=$(aws_call "$billing_region" budgets \
      describe-subscribers-for-notification \
      --account-id "$account_id" --budget-name "$budget_name" \
      --notification "$notification" --output json)
    count=$(printf '%s' "$subscribers" | jq -er '.Subscribers | length') ||
      fail "could not inspect budget subscribers"
    subscriber_count=$((subscriber_count + count))
    notification_index=$((notification_index + 1))
  done
  [ "$subscriber_count" -gt 0 ] ||
    fail "the selected AWS budget has no notification subscriber"

  actions=$(aws_call "$billing_region" budgets describe-budget-actions-for-budget \
    --account-id "$account_id" --budget-name "$budget_name" --output json)
  [ "$(printf '%s' "$actions" | jq -er '.Actions | length')" -eq 0 ] ||
    fail "the selected budget has mutation actions; use a notification-only budget"

  instance_filters=$(jq -nc \
    --arg location "$pricing_location" --arg instance "$instance_type" '[
      {Type:"TERM_MATCH",Field:"location",Value:$location},
      {Type:"TERM_MATCH",Field:"instanceType",Value:$instance},
      {Type:"TERM_MATCH",Field:"operatingSystem",Value:"Linux"},
      {Type:"TERM_MATCH",Field:"tenancy",Value:"Shared"},
      {Type:"TERM_MATCH",Field:"preInstalledSw",Value:"NA"},
      {Type:"TERM_MATCH",Field:"capacitystatus",Value:"Used"}
    ]')
  instance_prices=$(aws_call "$aws_region" pricing get-products \
    --service-code AmazonEC2 --filters "$instance_filters" \
    --max-results 100 --output json)
  instance_hourly=$(printf '%s' "$instance_prices" | extract_rate Hrs) ||
    fail "could not resolve the current on-demand instance price"

  storage_filters=$(jq -nc --arg location "$pricing_location" '[
    {Type:"TERM_MATCH",Field:"location",Value:$location},
    {Type:"TERM_MATCH",Field:"productFamily",Value:"Storage"},
    {Type:"TERM_MATCH",Field:"volumeApiName",Value:"gp3"}
  ]')
  storage_prices=$(aws_call "$aws_region" pricing get-products \
    --service-code AmazonEC2 --filters "$storage_filters" \
    --max-results 100 --output json)
  storage_gib_month=$(printf '%s' "$storage_prices" | extract_rate GB-Mo) ||
    fail "could not resolve the current gp3 storage price"

  ipv4_filters=$(jq -nc \
    --arg location "$pricing_location" \
    --arg usage "$pricing_ipv4_usage" '[
    {Type:"TERM_MATCH",Field:"location",Value:$location},
    {Type:"TERM_MATCH",Field:"usagetype",Value:$usage}
  ]')
  ipv4_prices=$(aws_call "$aws_region" pricing get-products \
    --service-code AmazonVPC --filters "$ipv4_filters" \
    --max-results 100 --output json)
  ipv4_hourly=$(printf '%s' "$ipv4_prices" | jq -er '
    [
      .PriceList[]
      | fromjson
      | select((.product.attributes.usagetype // "") | endswith("PublicIPv4:InUseAddress"))
      | .terms.OnDemand[]?.priceDimensions[]?
      | select(.unit == "Hrs")
      | .pricePerUnit.USD
      | tonumber
      | select(. > 0)
    ]
    | if length == 0 then error("price not found") else min end
  ') || fail "could not resolve the current public IPv4 price"

  created_at=$(jq -nr 'now | strftime("%Y-%m-%dT%H:%M:%SZ")')
  expires_at=$(jq -nr --argjson hours "$ttl_hours" \
    'now + ($hours * 3600) | strftime("%Y-%m-%dT%H:%M:%SZ")')
  estimated_cost=$(jq -nr \
    --argjson hours "$ttl_hours" \
    --argjson instance "$instance_hourly" \
    --argjson ipv4 "$ipv4_hourly" \
    --argjson storage "$storage_gib_month" \
    --argjson size "$root_volume_size" \
    '$hours * ($instance + $ipv4 + (($storage * $size) / 730))')

  umask 077
  mkdir -p "$cache_dir"
  jq -n \
    --arg account "$account_id" \
    --arg region "$aws_region" \
    --arg owner "$owner" \
    --arg created "$created_at" \
    --arg expires "$expires_at" \
    --arg cidr "$operator_cidr" \
    --rawfile public_key "$public_key_file" \
    --arg instance "$instance_type" \
    --argjson volume "$root_volume_size" '{
      aws_account_id: $account,
      aws_region: $region,
      owner: $owner,
      created_at: $created,
      expires_at: $expires,
      operator_cidr: $cidr,
      ssh_public_key: ($public_key | rtrimstr("\n")),
      instance_type: $instance,
      root_volume_size_gib: $volume
    }' >"$runtime_vars"

  jq -n \
    --arg profile "$aws_profile" \
    --arg account "$account_id" \
    --arg arn "$caller_arn" \
    --arg region "$aws_region" \
    --arg budget "$budget_name" \
    --arg expires "$expires_at" \
    --argjson free_tier "$free_tier_summary" \
    --argjson estimated "$estimated_cost" '{
      schema_version: 1,
      aws_profile: $profile,
      account_id: $account,
      caller_arn: $arn,
      aws_region: $region,
      budget_name: $budget,
      free_tier: $free_tier,
      expires_at: $expires,
      estimated_cost_usd_before_tax_and_transfer: $estimated
    }' >"$session_file"

  cat <<EOF
AWS reference-VM gate passed
  caller:          $caller_arn
  account:         $account_id
  region:          $aws_region
  Free Tier plan:  $free_tier_summary
  budget:          $budget_name ($budget_limit, $notification_count alert(s), $subscriber_count subscriber(s), no actions)
  instance:        $instance_type at USD $instance_hourly/hour
  root volume:     $root_volume_size GiB gp3 at USD $storage_gib_month/GiB-month
  public IPv4:     one temporary address at USD $ipv4_hourly/hour
  expiry:          $expires_at ($ttl_hours hour(s))
  estimate:        USD $(printf '%.4f' "$estimated_cost") before tax and variable data transfer
  excluded:        NAT gateway, Elastic IP, load balancer, paid AMI
EOF

  tofu -chdir="$terraform_root" plan \
    -var-file="$runtime_vars" -out="$create_plan"
  plan_sha=$(shasum -a 256 "$create_plan" | awk '{print $1}')
  jq --arg sha "$plan_sha" '. + {create_plan_sha256:$sha}' \
    "$session_file" >"$session_file.tmp"
  mv "$session_file.tmp" "$session_file"

  echo "Saved reviewed plan: $create_plan"
  echo "Apply confirmation: CONFIRM=aws-apply-$profile-$account_id make aws-apply"
}

apply_plan()
{
  load_session
  expected="aws-apply-$profile-$session_account_id"
  [ "${CONFIRM:-}" = "$expected" ] ||
    fail "set CONFIRM=$expected to create the AWS reference VM"
  [ -r "$create_plan" ] || fail "saved create plan is missing; run make aws-plan"
  require_live_session
  for tool in aws jq shasum tofu; do
    require_tool "$tool"
  done
  expected_sha=$(jq -er '.create_plan_sha256' "$session_file") ||
    fail "planned session has no create-plan digest"
  actual_sha=$(shasum -a 256 "$create_plan" | awk '{print $1}')
  [ "$actual_sha" = "$expected_sha" ] ||
    fail "saved create plan changed after review; run make aws-plan again"
  verify_planned_identity

  echo "Creating only the reviewed AWS boundary in account $account_id ($aws_region)."
  tofu -chdir="$terraform_root" apply "$create_plan"

  outputs=$(tofu -chdir="$terraform_root" output -json)
  instance_id=$(printf '%s' "$outputs" | jq -er '.instance_id.value')
  public_ip=$(printf '%s' "$outputs" | jq -er '.public_ip.value')
  ssh_user=$(printf '%s' "$outputs" | jq -er '.ssh_user.value')
  aws_call "$aws_region" ec2 wait instance-status-ok \
    --instance-ids "$instance_id"

  umask 077
  printf '%s' "$outputs" | jq '{
    all: {
      children: {
        incus_hosts: {
          hosts: {
            "incus-reference-01": {
              ansible_host: .public_ip.value,
              ansible_user: .ssh_user.value,
              debian_prepare_stable_target: true
            }
          }
        }
      }
    }
  }' >"$inventory_file"

  echo "AWS instance is healthy: $instance_id ($public_ip)"
  echo "Generated ignored inventory: $inventory_file"
  echo "Verify and accept the SSH host key before running Ansible."
  echo "Teardown confirmation: CONFIRM=aws-destroy-$profile-$account_id INCUS_SUBSTRATE_DESTROYED=true make aws-destroy"
}

destroy()
{
  load_session
  expected="aws-destroy-$profile-$session_account_id"
  [ "${CONFIRM:-}" = "$expected" ] ||
    fail "set CONFIRM=$expected to destroy the AWS reference VM boundary"
  [ "${INCUS_SUBSTRATE_DESTROYED:-}" = "true" ] ||
    fail "set INCUS_SUBSTRATE_DESTROYED=true after provider-owned Incus resources are gone"
  for tool in aws jq tofu; do
    require_tool "$tool"
  done
  verify_planned_identity

  echo "Planning destruction only in account $account_id ($aws_region)."
  tofu -chdir="$terraform_root" plan -destroy \
    -var-file="$runtime_vars" -out="$destroy_plan"
  tofu -chdir="$terraform_root" show "$destroy_plan"
  echo "Destroying the displayed AWS bootstrap boundary."
  tofu -chdir="$terraform_root" apply "$destroy_plan"
  rm -f "$create_plan" "$destroy_plan" "$inventory_file"
  echo "AWS destroy finished. Run make aws-orphan-check with the same PROFILE and AWS_PROFILE."
}

orphan_check()
{
  load_session
  for tool in aws jq tofu; do
    require_tool "$tool"
  done
  verify_planned_identity

  state_resources=$(tofu -chdir="$terraform_root" state list 2>/dev/null || true)
  [ -z "$state_resources" ] || {
    printf '%s\n' "$state_resources" >&2
    fail "the AWS bootstrap state still contains resources"
  }

  tagged=$(aws_call "$aws_region" resourcegroupstaggingapi get-resources \
    --tag-filters "Key=Project,Values=$project_tag" --output json)
  tagged_count=$(printf '%s' "$tagged" |
    jq -er '.ResourceTagMappingList | length') ||
    fail "could not inspect tagged AWS resources"

  tagged_arns=$(printf '%s' "$tagged" |
    jq -er '.ResourceTagMappingList[].ResourceARN') ||
    [ "$tagged_count" -eq 0 ] || fail "could not inspect tagged AWS resources"
  unknown_tagged_arns=$(printf '%s\n' "$tagged_arns" | awk '
    /:(instance|volume|vpc|subnet|internet-gateway|route-table|security-group|security-group-rule|key-pair|network-interface)\// { next }
    NF { print }
  ')
  [ -z "$unknown_tagged_arns" ] || {
    printf '%s\n' "$unknown_tagged_arns" >&2
    fail "unknown tagged AWS resource types remain after destroy"
  }

  tag_filter="Name=tag:Project,Values=$project_tag"
  live_resources=$(
    aws_call "$aws_region" ec2 describe-instances \
      --filters "$tag_filter" \
        "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped" \
      --query 'Reservations[].Instances[].InstanceId' --output text
    aws_call "$aws_region" ec2 describe-volumes --filters "$tag_filter" \
      --query 'Volumes[].VolumeId' --output text
    aws_call "$aws_region" ec2 describe-vpcs --filters "$tag_filter" \
      --query 'Vpcs[].VpcId' --output text
    aws_call "$aws_region" ec2 describe-subnets --filters "$tag_filter" \
      --query 'Subnets[].SubnetId' --output text
    aws_call "$aws_region" ec2 describe-internet-gateways --filters "$tag_filter" \
      --query 'InternetGateways[].InternetGatewayId' --output text
    aws_call "$aws_region" ec2 describe-route-tables --filters "$tag_filter" \
      --query 'RouteTables[].RouteTableId' --output text
    aws_call "$aws_region" ec2 describe-security-groups --filters "$tag_filter" \
      --query 'SecurityGroups[].GroupId' --output text
    aws_call "$aws_region" ec2 describe-security-group-rules --filters "$tag_filter" \
      --query 'SecurityGroupRules[].SecurityGroupRuleId' --output text
    aws_call "$aws_region" ec2 describe-key-pairs --filters "$tag_filter" \
      --query 'KeyPairs[].KeyPairId' --output text
    aws_call "$aws_region" ec2 describe-network-interfaces --filters "$tag_filter" \
      --query 'NetworkInterfaces[].NetworkInterfaceId' --output text
  )
  [ -z "$live_resources" ] || {
    printf '%s\n' "$live_resources" | tr '\t' '\n' >&2
    fail "live AWS resources remain after destroy"
  }

  if [ "$tagged_count" -ne 0 ]; then
    echo "AWS tagging index reports $tagged_count deleted-resource tombstone(s); direct EC2 checks found no live declared-boundary resources."
  fi

  echo "No OpenTofu state resources or live AWS resources tagged Project=$project_tag remain."
}

require_profile
case "$action" in
  plan) plan ;;
  apply) apply_plan ;;
  destroy) destroy ;;
  orphan-check) orphan_check ;;
  *) fail "usage: $0 {plan|apply|destroy|orphan-check}" ;;
esac
