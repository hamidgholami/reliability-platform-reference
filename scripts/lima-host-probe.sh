#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

fail()
{
  echo "ERROR: $*" >&2
  exit 1
}

for command_name in limactl jq system_profiler sw_vers uname; do
  command -v "$command_name" >/dev/null 2>&1 ||
    fail "required command is missing: ${command_name}"
done

platform="$(uname -s)"
architecture="$(uname -m)"
[ "$platform" = "Darwin" ] || fail "Lima VZ validation requires macOS"
[ "$architecture" = "arm64" ] || fail "the reviewed harness requires arm64"

macos_version="$(sw_vers -productVersion)"
chip="$(system_profiler SPHardwareDataType 2>/dev/null |
  awk -F ': ' '/Chip:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
memory="$(system_profiler SPHardwareDataType 2>/dev/null |
  awk -F ': ' '/Memory:/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}')"
[ -n "$chip" ] || fail "could not determine the Apple chip family"

case "$chip" in
  "Apple M"[3-9]|"Apple M"[1-9][0-9]*) nested_eligible=true ;;
  *) nested_eligible=false ;;
esac

lima_version="$(limactl --version | awk '{print $3}')"
vm_types="$(limactl info 2>/dev/null | jq -r '.vmTypes | join(",")')"
instance_count="$(limactl list --json 2>/dev/null | jq -s 'length')"

limactl validate /opt/homebrew/share/lima/templates/debian-13.yaml \
  >/dev/null 2>&1 || fail "the installed Debian 13 template is invalid"

debian_image="$(
  limactl template yq template:debian-13 \
    '.images[] | select(.arch == "aarch64") | .location' 2>/dev/null |
    sed -n '1p'
)"
debian_digest="$(
  limactl template yq template:debian-13 \
    '.images[] | select(.arch == "aarch64") | .digest' 2>/dev/null |
    sed -n '1p'
)"

if limactl start --help | grep -q -- '--nested-virt'; then
  nested_flag=true
else
  nested_flag=false
fi

if [ -x /opt/socket_vmnet/bin/socket_vmnet ]; then
  socket_vmnet=present
else
  socket_vmnet=absent
fi

if [ -f /private/etc/sudoers.d/lima ]; then
  lima_sudoers=present
else
  lima_sudoers=absent
fi

cat <<EOF
platform=${platform}
architecture=${architecture}
macos_version=${macos_version}
chip_family=${chip}
memory=${memory}
lima_version=${lima_version}
lima_vm_types=${vm_types}
lima_instances=${instance_count}
debian_13_template=valid
debian_13_arm64_image=${debian_image}
debian_13_arm64_digest=${debian_digest}
nested_virtualization_host_eligible=${nested_eligible}
nested_virtualization_cli_flag=${nested_flag}
socket_vmnet_secure_install=${socket_vmnet}
lima_sudoers=${lima_sudoers}
EOF
