#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

gitleaks dir --redact --verbose --no-banner .

if git rev-parse --verify HEAD >/dev/null 2>&1; then
  gitleaks git --redact --verbose --no-banner .
else
  echo "No commits exist yet; Git-history scan will begin after the first human commit."
fi
