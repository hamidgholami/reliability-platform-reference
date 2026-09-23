<!--
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
-->

# AWS reference VM

This runbook creates the short-lived Debian 13 host used for Phase 1 deployment
acceptance. It does not create Incus projects, networks, storage, profiles, or
containers. The AWS root owns one isolated VPC path, one EC2 key-pair record,
one `t4g.small` instance, one encrypted 30 GiB `gp3` root volume, and one
temporary public IPv4 address.

## One-time account preparation

1. Protect the AWS root user with MFA and do not use root credentials here.
2. Install AWS CLI v2 on the Mac with `brew install awscli`.
3. For a standalone account, attach AWS's managed
   `SignInLocalDevelopmentAccess` policy to a named, non-root IAM user. Use
   `aws login` to obtain temporary credentials; do not create access keys for
   this workflow or put credentials in this repository.
4. Give that principal the planning permissions below. They are read-only and
   intentionally cannot create the reference VM. Add the separately reviewed
   lifecycle policy only immediately before the paid apply milestone.
5. In AWS Billing, create a small monthly `COST` budget with at least one email
   notification and no automated budget action. Confirm the subscription email.

The workflow reads the existing budget; it never creates, changes, or deletes
account-level billing controls.

Do not enable AWS Organizations or IAM Identity Center only for this small lab
account. If they are already configured, an Identity Center profile is also a
valid short-lived authentication path.

### Planning policy

Create a customer-managed policy such as `RprP1PlanReadOnly` with this document
and attach it to the operator. `DescribeBudgetActionsForBudget` is required so
the gate can prove that the chosen budget has no automated mutation action.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadPlanningGates",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity",
        "freetier:GetAccountPlanState",
        "budgets:ViewBudget",
        "budgets:DescribeBudgetActionsForBudget",
        "aws-portal:ViewBilling",
        "pricing:GetProducts",
        "tag:GetResources",
        "ec2:Describe*",
        "ec2:GetConsoleOutput"
      ],
      "Resource": "*"
    }
  ]
}
```

### Temporary lifecycle policy

Immediately before an approved apply, attach a second customer-managed policy
such as `RprP1FrankfurtLifecycle`. Keep it attached until `aws-destroy` and the
orphan check succeed, then detach it. It permits only the EC2/VPC operations
needed by this root and only through the Frankfurt endpoint; it grants no IAM,
S3, Route 53, load-balancer, NAT gateway, or billing mutations.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageReferenceBoundaryInFrankfurt",
      "Effect": "Allow",
      "Action": [
        "ec2:AssociateRouteTable",
        "ec2:AttachInternetGateway",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateInternetGateway",
        "ec2:CreateRoute",
        "ec2:CreateRouteTable",
        "ec2:CreateSecurityGroup",
        "ec2:CreateSubnet",
        "ec2:CreateTags",
        "ec2:CreateVpc",
        "ec2:DeleteInternetGateway",
        "ec2:DeleteKeyPair",
        "ec2:DeleteRoute",
        "ec2:DeleteRouteTable",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteSubnet",
        "ec2:DeleteTags",
        "ec2:DeleteVpc",
        "ec2:DetachInternetGateway",
        "ec2:DisassociateRouteTable",
        "ec2:ImportKeyPair",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyInstanceMetadataOptions",
        "ec2:ModifySubnetAttribute",
        "ec2:ModifyVpcAttribute",
        "ec2:ReplaceRoute",
        "ec2:ReplaceRouteTableAssociation",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RunInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "eu-central-1"
        }
      }
    }
  ]
}
```

The wildcard resource is intentional because EC2 launch and VPC topology
operations span several resource types, and some do not support resource-level
authorization. The explicit action list, Frankfurt condition, isolated
OpenTofu state, exact confirmation, and short attachment window form the
boundary for this single-account exercise.

## Per-session preparation

Authenticate and verify that the profile is not the root user:

```sh
aws login --profile rpr-p1 --region eu-central-1
aws sts get-caller-identity --profile rpr-p1
```

The identity must be the intended non-root operator. For an existing IAM
Identity Center profile, use `aws sso login --profile rpr-p1` instead.

Create a dedicated Ed25519 key if one does not already exist:

```sh
ssh-keygen -t ed25519 -a 64 -f ~/.ssh/rpr-p1 -C rpr-p1
chmod 600 ~/.ssh/rpr-p1
gpg-connect-agent updatestartuptty /bye >/dev/null
ssh-add -t 43200 ~/.ssh/rpr-p1
ssh-add -l
```

Enter a strong passphrase when `ssh-keygen` prompts. The private key stays on
the workstation; OpenTofu sends only the `.pub` file to AWS. This workstation
uses GnuPG's OpenSSH-agent interface, so `ssh-add` imports the protected key
into `gpg-agent` and makes it available to SSH and Ansible for the bounded
session. Do not use the macOS-specific `--apple-use-keychain` option while
`SSH_AUTH_SOCK` points to the GnuPG agent.

Find the Mac's current public IPv4 from a trusted network. The security group
accepts exactly one `/32`; if the address changes, create and apply a fresh
plan:

```sh
dig +short myip.opendns.com @resolver1.opendns.com
```

Then export the non-secret execution inputs:

```sh
export PROFILE=single-node-reference
export AWS_PROFILE=rpr-p1
export AWS_BUDGET_NAME=rpr-lab-monthly
export OWNER=hamidgholami
export OPERATOR_CIDR=203.0.113.10/32
export OPERATOR_PUBLIC_KEY_FILE="$HOME/.ssh/rpr-p1.pub"
export OPERATOR_SSH_IDENTITY_FILE="$HOME/.ssh/rpr-p1"
export TTL_HOURS=6
```

Replace the documentation address and example budget name. `AWS_REGION`
defaults to the currently reviewed `eu-central-1`; the first implementation
rejects other regions until their AMI availability and pricing mapping are
tested.

All EC2, VPC, AMI, and EBS discovery and resources stay in Frankfurt
(`eu-central-1`). AWS Budgets and Free Tier are account-level APIs queried
through `us-east-1`. Price List queries use its Frankfurt API endpoint, while
their product filter explicitly selects `EU (Frankfurt)`.

## Plan and apply

Run all workstation checks, then run the live read-only gates and plan:

```sh
make check
make aws-plan
```

The plan command verifies the caller and account binding, rejects root
credentials, inspects the current Free Tier plan, requires a notification-only
cost budget, queries current EC2, `gp3`, and public IPv4 list prices, enforces a
maximum 12-hour lifetime, and writes its plan and inputs only below the ignored
`.cache/aws-single-node/` directory. Treat credits and Free Tier eligibility as
possible discounts, never as a guarantee of zero cost. Some established
accounts have no record in the newer Account Plan API; that response is
recorded as `NO_ACCOUNT_PLAN_RECORD` and the estimate assumes no discount.

Review the plan. It must show the official Debian owner `136693071363`, arm64,
the expected tags and expiry, and only the documented resource boundary. Use
the account ID printed by `aws-plan` in the exact confirmation:

```sh
CONFIRM=aws-apply-single-node-reference-123456789012 make aws-apply
```

Apply verifies the saved plan digest and caller account again. After EC2 status
checks pass, it writes the non-secret inventory to
`.cache/aws-single-node/hosts.json`.

Before Ansible, make one direct SSH connection and compare the presented host
key fingerprint with the EC2 console output. Do not disable host-key checking.
Then use the generated inventory:

```sh
export INVENTORY=.cache/aws-single-node/hosts.json
export TARGET_HOST=incus-reference-01

make preflight
make baseline-check
CONFIRM=baseline-single-node-reference-incus-reference-01 make baseline
make validate-baseline
make preflight-incus
CONFIRM=bootstrap-incus-single-node-reference-incus-reference-01 \
  make bootstrap-incus
make validate-incus
```

Run the baseline and Incus mutation commands a second time during the milestone
to prove idempotence. The Ansible wrapper accepts
`OPERATOR_SSH_IDENTITY_FILE`, but it may be omitted when a correctly configured
SSH agent supplies the key.

## Incus provider lifecycle

After `validate-incus` records the server certificate fingerprint, follow the
[reference-VM enrollment](incus-client-trust.md#reference-vm-enrollment). It
uses distinct human and OpenTofu remotes and a distinct provider cache, so the
preserved Lima client identities and OpenTofu state are not overwritten.

Review and apply the five-resource provider plan, validate it, and prove a
second no-change apply:

```sh
make plan
CONFIRM=apply-incus-single-node-reference-rpr-reference-tofu make apply
make validate
make plan
CONFIRM=apply-incus-single-node-reference-rpr-reference-tofu make apply
```

Then exercise provider-only teardown and clean recreation:

```sh
CONFIRM=destroy-incus-single-node-reference-rpr-reference-tofu make destroy
make incus-client-check
make plan
CONFIRM=apply-incus-single-node-reference-rpr-reference-tofu make apply
make validate
```

Before destroying the AWS layer, perform the final provider destroy, verify
that its state is empty, and revoke the two reference client certificates as
described in the trust runbook. Do not revoke or remove the Lima identities.

## Teardown and orphan check

Provider-owned Incus resources must be destroyed first once P1-05 creates
them. Then inspect and destroy only the AWS bootstrap state:

```sh
CONFIRM=aws-destroy-single-node-reference-123456789012 \
  INCUS_SUBSTRATE_DESTROYED=true make aws-destroy
make aws-orphan-check
```

Destroy removes the generated inventory and saved plans after OpenTofu
succeeds. The orphan check fails if the local state still contains resources or
if resource-specific EC2 APIs return a live resource tagged
`Project=reliability-platform-reference`. AWS's tagging index can temporarily
return deleted-resource tombstones; the check reports known tombstones only
after the authoritative EC2 checks find no live declared-boundary resource. It
fails closed for an unknown tagged resource type and does not inspect unrelated,
untagged account resources.

No domain change, DNS record, password, TLS certificate, TOTP seed, Vault
token, or Kubernetes credential is needed for this Phase 1 host run.
