# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

MARKDOWNLINT_VERSION ?= 0.23.2
TOFU_VERSION ?= 1.12.6
ANSIBLE_ENV = ANSIBLE_CONFIG=$(CURDIR)/ansible.cfg ANSIBLE_HOME=$(CURDIR)/.cache/ansible ANSIBLE_COLLECTIONS_PATH=$(CURDIR)/.cache/ansible/collections ANSIBLE_LOCAL_TEMP=$(CURDIR)/.cache/ansible/tmp

.DEFAULT_GOAL := help

.PHONY: help setup setup-python setup-hcl doctor lint lint-markdown lint-license lint-ansible \
	syntax-ansible lint-hcl validate-hcl test-hcl scan-secrets check test-local \
	lima-validate lima-up lima-stop lima-delete preflight baseline \
	bootstrap-incus plan apply validate destroy aws-plan aws-apply \
	aws-destroy aws-orphan-check

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

syntax-ansible: ## Parse the sanitized YAML inventory without contacting a host.
	@$(ANSIBLE_ENV) .venv/bin/ansible-inventory --inventory ansible/inventories/single-node-reference/hosts.example.yml --list >/dev/null

lint-hcl: ## Check OpenTofu formatting without changing files.
	@tofu fmt -check -recursive infrastructure

validate-hcl: ## Validate initialized HCL without credentials or network access.
	@./scripts/validate-hcl.sh

test-hcl: ## Test the AWS safety contract with a mocked provider only.
	@tofu -chdir=infrastructure/bootstrap/aws-single-node test

scan-secrets: ## Scan Git content and the working tree with Gitleaks.
	@./scripts/scan-secrets.sh

check: lint syntax-ansible validate-hcl test-hcl scan-secrets ## Run every non-mutating repository check.

test-local: check ## Run the complete workstation-only test suite.

lima-validate: ## Validate the optional Lima YAML; do not create a VM.
	@./scripts/lima-lifecycle.sh validate

lima-up: ## Create the optional VM (requires PROFILE and CONFIRM).
	@./scripts/lima-lifecycle.sh up

lima-stop: ## Stop the optional Lima VM without deleting it.
	@./scripts/lima-lifecycle.sh stop

lima-delete: ## Delete the optional VM (requires PROFILE and CONFIRM).
	@./scripts/lima-lifecycle.sh delete

preflight: ## Unavailable until P1-02: validate a selected Debian target.
	@./scripts/not-implemented.sh preflight P1-02

baseline: ## Unavailable until P1-02: prepare and harden the Debian target.
	@./scripts/not-implemented.sh baseline P1-02

bootstrap-incus: ## Unavailable until P1-03: install and initialize Incus.
	@./scripts/not-implemented.sh bootstrap-incus P1-03

plan: ## Unavailable until P1-05: plan provider-owned Incus resources.
	@./scripts/not-implemented.sh plan P1-05

apply: ## Unavailable until P1-05: apply provider-owned Incus resources.
	@./scripts/not-implemented.sh apply P1-05

validate: ## Unavailable until P1-05: validate the Incus substrate.
	@./scripts/not-implemented.sh validate P1-05

destroy: ## Unavailable until P1-05: destroy provider-owned Incus resources.
	@./scripts/not-implemented.sh destroy P1-05

aws-plan: ## Unavailable until P1-04: plan the minimal AWS VM boundary.
	@./scripts/not-implemented.sh aws-plan P1-04

aws-apply: ## Unavailable until P1-04: create the minimal AWS VM boundary.
	@./scripts/not-implemented.sh aws-apply P1-04

aws-destroy: ## Unavailable until P1-04: destroy the minimal AWS VM boundary.
	@./scripts/not-implemented.sh aws-destroy P1-04

aws-orphan-check: ## Unavailable until P1-04: query tagged AWS leftovers.
	@./scripts/not-implemented.sh aws-orphan-check P1-04
