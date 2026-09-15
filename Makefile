# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

MARKDOWNLINT_VERSION ?= 0.23.2
TOFU_VERSION ?= 1.12.6
ANSIBLE_ENV = ANSIBLE_CONFIG=$(CURDIR)/ansible.cfg ANSIBLE_HOME=$(CURDIR)/.cache/ansible ANSIBLE_COLLECTIONS_PATH=$(CURDIR)/.cache/ansible/collections ANSIBLE_LOCAL_TEMP=$(CURDIR)/.cache/ansible/tmp

.DEFAULT_GOAL := help

.PHONY: help setup setup-python setup-hcl doctor lint lint-markdown lint-license lint-ansible \
	syntax-ansible lint-hcl validate-hcl test-hcl scan-secrets check test-local \
	lima-validate lima-up lima-start lima-stop lima-inventory lima-delete \
	preflight baseline-check baseline \
	validate-baseline preflight-incus bootstrap-incus validate-incus \
	incus-client-check test-ansible-safety test-lima-safety \
	test-incus-substrate-safety \
	bootstrap-incus plan apply validate destroy aws-plan aws-apply \
	aws-destroy aws-orphan-check test-aws-safety

help: ## Show the Phase 1 operator interface and availability.
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z_-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: setup-python setup-hcl ## Install pinned local validation dependencies; create no infrastructure.

setup-python: ## Create .venv and install pinned Ansible dependencies locally.
	@mkdir -p .cache/ansible/tmp .cache/ansible/collections
	@python3 -m venv .venv
	@.venv/bin/python -m pip install --requirement requirements.txt
	@SSL_CERT_FILE="$$(.venv/bin/python -m certifi)" $(ANSIBLE_ENV) .venv/bin/ansible-galaxy collection install --requirements-file ansible/requirements.yml

setup-hcl: ## Download only providers recorded in committed lock files.
	@./scripts/init-hcl.sh

doctor: ## Check tools required by active Phase 1 static validation.
	@TOFU_VERSION=$(TOFU_VERSION) ./scripts/doctor.sh

lint: lint-markdown lint-license lint-ansible lint-hcl ## Run all static linters.

lint-markdown: ## Lint all Markdown with a pinned markdownlint-cli2 release.
	@npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION) "**/*.md" "#node_modules" "#.git" "#.cache" "#.venv" "#**/.terraform"

lint-license: ## Verify repository license and attribution policy.
	@./scripts/check-license.sh

lint-ansible: ## Lint Ansible content with the pinned virtual environment.
	@$(ANSIBLE_ENV) .venv/bin/ansible-lint ansible

syntax-ansible: ## Syntax-check the Phase 1 Ansible inventory and playbooks offline.
	@$(ANSIBLE_ENV) .venv/bin/ansible-inventory --inventory ansible/inventories/single-node-reference/hosts.example.yml --list >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/preflight.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/baseline.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/validate-baseline.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/preflight-incus.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/bootstrap-incus.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/validate-incus.yml >/dev/null

lint-hcl: ## Check OpenTofu formatting without changing files.
	@tofu fmt -check -recursive infrastructure

validate-hcl: ## Validate initialized HCL without credentials or network access.
	@./scripts/validate-hcl.sh

test-hcl: ## Test the AWS and Incus safety contracts with mocked providers only.
	@tofu -chdir=infrastructure/bootstrap/aws-single-node test
	@tofu -chdir=infrastructure/incus test

test-ansible-safety: ## Test Ansible target and confirmation fail-closed behavior.
	@./tests/ansible-target-safety.sh

test-lima-safety: ## Test Lima lifecycle guards and generated inventory offline.
	@./tests/lima-lifecycle-safety.sh

test-incus-substrate-safety: ## Test Incus provider trust guards offline.
	@./tests/incus-substrate-safety.sh

test-aws-safety: ## Test AWS profile, exposure, TTL, and confirmation guards offline.
	@./tests/aws-reference-safety.sh

scan-secrets: ## Scan Git content and the working tree with Gitleaks.
	@./scripts/scan-secrets.sh

check: lint syntax-ansible validate-hcl test-hcl test-ansible-safety test-lima-safety test-incus-substrate-safety test-aws-safety scan-secrets ## Run every non-mutating repository check.

test-local: check ## Run the complete workstation-only test suite.

lima-validate: ## Validate the optional Lima YAML; do not create a VM.
	@./scripts/lima-lifecycle.sh validate

lima-up: ## Create the optional VM (requires PROFILE and CONFIRM).
	@./scripts/lima-lifecycle.sh up

lima-start: ## Restart the existing optional VM (requires PROFILE and CONFIRM).
	@./scripts/lima-lifecycle.sh start

lima-stop: ## Stop the optional Lima VM (requires PROFILE).
	@./scripts/lima-lifecycle.sh stop

lima-inventory: ## Generate ignored Ansible inventory for the running Lima VM.
	@./scripts/lima-lifecycle.sh inventory

lima-delete: ## Delete the optional VM (requires PROFILE and CONFIRM).
	@./scripts/lima-lifecycle.sh delete

preflight: ## Read-only validation of an explicitly selected Debian target.
	@./scripts/ansible-target.sh preflight

baseline-check: ## Preview the selected target baseline in Ansible check mode.
	@./scripts/ansible-target.sh baseline-check

baseline: ## Prepare and harden a selected target (requires exact CONFIRM).
	@./scripts/ansible-target.sh baseline

validate-baseline: ## Validate the baseline and write ignored local evidence.
	@./scripts/ansible-target.sh validate-baseline

preflight-incus: ## Read-only validation before installing or configuring Incus.
	@./scripts/ansible-target.sh preflight-incus

bootstrap-incus: ## Install and initialize standalone Incus (requires exact CONFIRM).
	@./scripts/ansible-target.sh bootstrap-incus

validate-incus: ## Validate Incus API health and write ignored local evidence.
	@./scripts/ansible-target.sh validate-incus

incus-client-check: ## Verify the isolated OpenTofu client trust boundary.
	@./scripts/incus-substrate.sh preflight

plan: ## Verify Incus trust and save a non-destructive substrate plan.
	@./scripts/incus-substrate.sh plan

apply: ## Apply the reviewed Incus substrate plan (requires exact CONFIRM).
	@./scripts/incus-substrate.sh apply

validate: ## Validate the Incus substrate and write ignored local evidence.
	@./scripts/incus-substrate.sh validate

destroy: ## Destroy only provider-owned Incus resources (requires exact CONFIRM).
	@./scripts/incus-substrate.sh destroy

aws-plan: ## Verify AWS safety/cost gates and save the minimal VM plan.
	@./scripts/aws-reference.sh plan

aws-apply: ## Apply the reviewed AWS plan and generate ignored inventory.
	@./scripts/aws-reference.sh apply

aws-destroy: ## Destroy only the state-owned AWS bootstrap boundary.
	@./scripts/aws-reference.sh destroy

aws-orphan-check: ## Check local state and AWS for tagged leftovers.
	@./scripts/aws-reference.sh orphan-check
