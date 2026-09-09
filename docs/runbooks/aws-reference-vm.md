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
3. Configure a named, non-root CLI profile. Prefer a short-lived IAM Identity
   Center session; do not put access keys in this repository.
4. Give that principal the EC2 lifecycle permissions for the declared boundary
   and read permissions for STS identity, Price List, Free Tier, Budgets, and
   Resource Groups Tagging. Keep billing-console access enabled for the budget
   checks.
5. In AWS Billing, create a small monthly `COST` budget with at least one email
   notification and no automated budget action. Confirm the subscription email.

The workflow reads the existing budget; it never creates, changes, or deletes
account-level billing controls.

## Per-session preparation

Authenticate and verify that the profile is not the root user:

```sh
aws sso login --profile rpr-p1
aws sts get-caller-identity --profile rpr-p1
```

If the profile does not use IAM Identity Center, use its normal short-lived
credential process instead of `aws sso login`.

Create a dedicated Ed25519 key if one does not already exist:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/rpr-p1 -C rpr-p1
chmod 600 ~/.ssh/rpr-p1
```

Find the Mac's current public IPv4 from a trusted network. The security group
accepts exactly one `/32`; if the address changes, create and apply a fresh
plan. Then export the non-secret execution inputs:

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
possible discounts, never as a guarantee of zero cost.

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
if AWS still returns a live resource tagged
`Project=reliability-platform-reference`. It does not inspect unrelated,
untagged account resources.

No domain change, DNS record, password, TLS certificate, TOTP seed, Vault
token, or Kubernetes credential is needed for this Phase 1 host run.
