#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

failures=0

require_file() {
  if [ ! -s "$1" ]; then
    echo "Missing or empty required file: $1" >&2
    failures=$((failures + 1))
  fi
}

for required in LICENSE NOTICE AUTHORS.md docs/license-policy.md; do
  require_file "$required"
done

if [ -f LICENSE ] && ! grep -q "Apache License" LICENSE; then
  echo "LICENSE does not identify the Apache License." >&2
  failures=$((failures + 1))
fi

if [ -f NOTICE ] && ! grep -q "Copyright 2026 Hamid Gholami" NOTICE; then
  echo "NOTICE does not contain the expected initial attribution." >&2
  failures=$((failures + 1))
fi

for source_file in Makefile .editorconfig .gitignore .gitleaks.toml \
  .markdownlint-cli2.yaml \
  .ansible-lint ansible.cfg requirements.txt ansible/requirements.yml \
  pki/offline-root/root-ca.cnf \
  pki/offline-root/openbao-intermediate-policy.cnf \
  ansible/inventories/single-node-reference/hosts.example.yml \
  ansible/inventories/single-node-reference/group_vars/incus_hosts.yml \
  ansible/tasks/target_preflight.yml \
  ansible/playbooks/preflight.yml ansible/playbooks/baseline.yml \
  ansible/playbooks/validate-baseline.yml \
  ansible/playbooks/preflight-incus.yml \
  ansible/playbooks/bootstrap-incus.yml \
  ansible/playbooks/validate-incus.yml \
  ansible/roles/debian_prepare/defaults/main.yml \
  ansible/roles/debian_prepare/handlers/main.yml \
  ansible/roles/debian_prepare/meta/argument_specs.yml \
  ansible/roles/debian_prepare/tasks/main.yml \
  ansible/roles/debian_prepare/tasks/packages.yml \
  ansible/roles/debian_prepare/tasks/operator.yml \
  ansible/roles/debian_prepare/tasks/journald.yml \
  ansible/roles/debian_prepare/tasks/resolver.yml \
  ansible/roles/incus_host/defaults/main.yml \
  ansible/roles/incus_host/meta/argument_specs.yml \
  ansible/roles/incus_host/tasks/main.yml \
  ansible/roles/incus_host/tasks/preflight.yml \
  ansible/roles/incus_host/tasks/validate.yml \
  ansible/roles/incus_host/templates/incus-preseed-v1.yml.j2 \
  lima/single-node.yaml \
  scripts/doctor.sh scripts/check-license.sh scripts/scan-secrets.sh \
  scripts/lima-host-probe.sh scripts/lima-lifecycle.sh \
  scripts/init-hcl.sh scripts/validate-hcl.sh scripts/not-implemented.sh \
  scripts/ansible-target.sh scripts/openbao-pki.sh scripts/openbao-ceremony.sh \
  scripts/openbao-audit.sh scripts/openbao-audit-acceptance-remote.sh \
  scripts/openbao-bootstrap.sh \
  scripts/openbao-root-retirement.sh \
  scripts/openbao-root-retirement-remote.py \
  scripts/validate-openbao-bootstrap-tls.sh \
  tests/ansible-target-safety.sh \
  tests/fixtures/openbao-ceremony/incus \
  tests/offline-root-policy.sh \
  ansible/playbooks/bootstrap-openbao.yml \
  ansible/playbooks/prepare-openbao-pki.yml \
  ansible/playbooks/import-openbao-pki.yml \
  ansible/playbooks/rotate-openbao-certificate.yml \
  ansible/playbooks/configure-openbao-root-recovery.yml \
  ansible/playbooks/configure-machine-auth.yml \
  ansible/roles/openbao_bootstrap/defaults/main.yml \
  ansible/roles/openbao_bootstrap/meta/argument_specs.yml \
  ansible/roles/openbao_bootstrap/tasks/main.yml \
  ansible/roles/openbao_bootstrap/templates/bootstrap-admin.hcl.j2 \
  ansible/roles/openbao_bootstrap/templates/operator.hcl.j2 \
  ansible/roles/openbao_bootstrap/templates/machine-read.hcl.j2 \
  ansible/roles/openbao_pki/defaults/main.yml \
  ansible/roles/openbao_pki/meta/argument_specs.yml \
  ansible/roles/openbao_pki/tasks/main.yml \
  ansible/roles/openbao_pki/tasks/prepare.yml \
  ansible/roles/openbao_pki/tasks/import.yml \
  ansible/roles/openbao_pki/tasks/rotate.yml \
  ansible/roles/openbao_pki/templates/bootstrap-policy.hcl.j2 \
  ansible/roles/openbao_pki/templates/leaf-policy.hcl.j2 \
  ansible/roles/openbao_root_recovery/defaults/main.yml \
  ansible/roles/openbao_root_recovery/meta/argument_specs.yml \
  ansible/roles/openbao_root_recovery/tasks/main.yml \
  ansible/roles/openbao_root_recovery/templates/bootstrap-policy.hcl.j2 \
  ansible/roles/openbao_root_recovery/templates/root-generation-policy.hcl.j2 \
  infrastructure/bootstrap/aws-single-node/versions.tf \
  infrastructure/bootstrap/aws-single-node/variables.tf \
  infrastructure/bootstrap/aws-single-node/main.tf \
  infrastructure/bootstrap/aws-single-node/outputs.tf \
  infrastructure/bootstrap/aws-single-node/terraform.tfvars.example \
  infrastructure/bootstrap/aws-single-node/tests/safety.tftest.hcl \
  infrastructure/incus/versions.tf \
  .github/workflows/quality.yml; do
  if [ -f "$source_file" ] && \
    ! grep -q "SPDX-License-Identifier: Apache-2.0" "$source_file"; then
    echo "Missing Apache-2.0 SPDX identifier: $source_file" >&2
    failures=$((failures + 1))
  fi
done

if [ "$failures" -ne 0 ]; then
  exit 1
fi

echo "License and attribution checks passed."
