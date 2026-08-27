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

for source_file in Makefile .editorconfig .gitignore .markdownlint-cli2.yaml \
  scripts/doctor.sh scripts/check-license.sh scripts/scan-secrets.sh \
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
