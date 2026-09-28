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
	private-dns-primary-check private-dns-primary validate-private-dns-primary \
	incus-client-check test-ansible-safety test-lima-safety \
	test-incus-substrate-safety test-private-dns-safety test-openbao-safety \
	test-offline-root-policy openbao-pki-create openbao-pki-renew \
	validate-openbao-bootstrap-tls \
	private-dns-secrets configure-private-dns validate-private-dns \
	accept-private-dns configure-openbao openbao-status validate-openbao \
	initialize-openbao unseal-openbao accept-openbao-audit bootstrap-openbao \
	bootstrap-openbao-pki rotate-openbao-certificate retire-openbao-root-token \
	bootstrap-incus plan apply validate destroy aws-plan aws-apply \
	aws-destroy aws-orphan-check test-aws-safety

help: ## Show the operator interface and availability.
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

syntax-ansible: ## Syntax-check active Ansible inventories and playbooks offline.
	@$(ANSIBLE_ENV) .venv/bin/ansible-inventory --inventory ansible/inventories/single-node-reference/hosts.example.yml --list >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-inventory --inventory ansible/inventories/private-dns/hosts.example.yml --list >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-inventory --inventory ansible/inventories/openbao/hosts.example.yml --list >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/preflight.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/baseline.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/validate-baseline.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/preflight-incus.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/bootstrap-incus.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/validate-incus.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/configure-incus-dns-primary.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/single-node-reference/hosts.example.yml --syntax-check ansible/playbooks/validate-incus-dns-primary.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/private-dns/hosts.example.yml --syntax-check ansible/playbooks/configure-private-dns.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/private-dns/hosts.example.yml --syntax-check ansible/playbooks/validate-private-dns.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/openbao/hosts.example.yml --syntax-check ansible/playbooks/configure-openbao.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/openbao/hosts.example.yml --syntax-check ansible/playbooks/openbao-status.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/openbao/hosts.example.yml --syntax-check ansible/playbooks/validate-openbao.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/openbao/hosts.example.yml --syntax-check ansible/playbooks/bootstrap-openbao.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/openbao/hosts.example.yml --syntax-check ansible/playbooks/prepare-openbao-pki.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/openbao/hosts.example.yml --syntax-check ansible/playbooks/import-openbao-pki.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/openbao/hosts.example.yml --syntax-check ansible/playbooks/rotate-openbao-certificate.yml >/dev/null
	@$(ANSIBLE_ENV) .venv/bin/ansible-playbook --inventory ansible/inventories/openbao/hosts.example.yml --syntax-check ansible/playbooks/configure-openbao-root-recovery.yml >/dev/null

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

test-private-dns-safety: ## Test private DNS confirmation and secret-file guards offline.
	@./tests/private-dns-safety.sh

test-openbao-safety: ## Test OpenBao confirmation, TLS-input, and inventory guards offline.
	@./tests/openbao-safety.sh

test-offline-root-policy: ## Exercise the offline-root policy with throwaway synthetic keys.
	@./tests/offline-root-policy.sh

test-aws-safety: ## Test AWS profile, exposure, TTL, and confirmation guards offline.
	@./tests/aws-reference-safety.sh

scan-secrets: ## Scan Git content and the working tree with Gitleaks.
	@./scripts/scan-secrets.sh

check: lint syntax-ansible validate-hcl test-hcl test-ansible-safety test-lima-safety test-incus-substrate-safety test-private-dns-safety test-openbao-safety test-offline-root-policy test-aws-safety scan-secrets ## Run every non-mutating repository check.

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

private-dns-primary-check: ## Preview the private Incus DNS listener configuration.
	@./scripts/ansible-target.sh private-dns-primary-check

private-dns-primary: ## Enable the private Incus DNS listener (requires exact CONFIRM).
	@./scripts/ansible-target.sh private-dns-primary

validate-private-dns-primary: ## Validate the private Incus DNS listener.
	@./scripts/ansible-target.sh validate-private-dns-primary

incus-client-check: ## Verify the isolated OpenTofu client trust boundary.
	@./scripts/incus-substrate.sh preflight

private-dns-secrets: ## Generate protected synthetic TSIG inputs (requires exact CONFIRM).
	@./scripts/private-dns-secrets.sh

configure-private-dns: ## Configure both BIND secondaries (requires exact CONFIRM).
	@./scripts/private-dns.sh configure

validate-private-dns: ## Validate both BIND secondaries.
	@./scripts/private-dns.sh validate

accept-private-dns: ## Exercise DNS propagation and one-secondary continuity (requires exact CONFIRM).
	@./scripts/private-dns-acceptance.sh

validate-openbao-bootstrap-tls: ## Validate protected bootstrap certificate inputs and print public metadata.
	@./scripts/validate-openbao-bootstrap-tls.sh

openbao-pki-create: ## Create a protected local root CA and one-year OpenBao listener certificate.
	@./scripts/openbao-pki.sh create

openbao-pki-renew: ## Renew the OpenBao listener certificate and archive its previous input.
	@./scripts/openbao-pki.sh renew

configure-openbao: ## Install and configure OpenBao (requires protected TLS input and exact CONFIRM).
	@./scripts/openbao.sh configure

openbao-status: ## Read redacted OpenBao service and seal status.
	@./scripts/openbao.sh status

validate-openbao: ## Validate the OpenBao package, service, storage, audit, and TLS boundary.
	@./scripts/openbao.sh validate

initialize-openbao: ## Initialize OpenBao and create encrypted operator recovery material.
	@./scripts/openbao-ceremony.sh initialize

unseal-openbao: ## Unseal OpenBao from protected operator recovery material.
	@./scripts/openbao-ceremony.sh unseal

accept-openbao-audit: ## Exercise OpenBao audit writes, rotation, and fail-closed recovery.
	@./scripts/openbao-audit.sh

bootstrap-openbao: ## Configure and prove KV v2 and scoped policies with ephemeral tokens.
	@./scripts/openbao-bootstrap.sh kv

bootstrap-openbao-pki: ## Create, root-sign, import, and validate the online intermediate CA.
	@./scripts/openbao-bootstrap.sh pki

rotate-openbao-certificate: ## Issue or renew the OpenBao listener certificate (requires exact CONFIRM).
	@./scripts/openbao-bootstrap.sh leaf

retire-openbao-root-token: ## Prove authenticated recovery and retire the initial root token (requires exact CONFIRM).
	@./scripts/openbao-root-retirement.sh

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
