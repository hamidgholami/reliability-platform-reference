#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

missing=""
for tool in git make node npm npx gitleaks python3 jq tofu; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing="${missing} ${tool}"
  fi
done

if [ -n "$missing" ]; then
  echo "Missing required Phase 1 validation tools:${missing}" >&2
  exit 1
fi

if [ ! -x .venv/bin/ansible-lint ] || [ ! -x .venv/bin/ansible-inventory ]; then
  echo "Missing pinned Ansible environment; run: make setup" >&2
  exit 1
fi

if [ ! -d .cache/ansible/collections/ansible_collections/devsec/hardening ]; then
  echo "Missing pinned devsec.hardening collection; run: make setup-python" >&2
  exit 1
fi

required_tofu_version="${TOFU_VERSION:-1.12.6}"
tofu_version="$(tofu version -json | jq -r '.terraform_version')"
[ "$tofu_version" = "$required_tofu_version" ] || {
  echo "OpenTofu ${required_tofu_version} is required; found ${tofu_version}." >&2
  exit 1
}

echo "Phase 1 static-validation toolchain is available."

if command -v limactl >/dev/null 2>&1; then
  echo "Optional Lima detected: $(limactl --version)"
else
  echo "Optional Lima is not installed; reference-target testing remains available."
fi

if command -v incus >/dev/null 2>&1; then
  echo "Optional Incus workstation client detected: $(incus --version)"
else
  echo "Optional Incus client is not installed; run 'brew install incus' before P1-05."
fi
