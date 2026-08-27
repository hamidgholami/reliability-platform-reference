# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

MARKDOWNLINT_VERSION ?= 0.23.2

.DEFAULT_GOAL := help

.PHONY: help doctor lint lint-markdown lint-license scan-secrets check

help: ## Show the supported Phase 0 commands.
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z_-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

doctor: ## Check local tools required by Phase 0.
	@./scripts/doctor.sh

lint: lint-markdown lint-license ## Run documentation and license checks.

lint-markdown: ## Lint all Markdown with a pinned markdownlint-cli2 release.
	@npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION) "**/*.md" "#node_modules" "#.git"

lint-license: ## Verify repository license and attribution policy.
	@./scripts/check-license.sh

scan-secrets: ## Scan Git content and the working tree with Gitleaks.
	@./scripts/scan-secrets.sh

check: lint scan-secrets ## Run all Phase 0 checks.
