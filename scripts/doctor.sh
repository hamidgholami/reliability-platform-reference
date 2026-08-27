#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

missing=""
for tool in git make node npm npx gitleaks; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing="${missing} ${tool}"
  fi
done

if [ -n "$missing" ]; then
  echo "Missing required Phase 0 tools:${missing}" >&2
  exit 1
fi

echo "Phase 0 toolchain is available."

