#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

target="${1:-requested target}"
work_item="${2:-a later work item}"

echo "${target} is intentionally unavailable until ${work_item}." >&2
echo "No infrastructure or target was changed." >&2
exit 2
