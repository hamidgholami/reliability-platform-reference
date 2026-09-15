#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu

output_file=$(mktemp)
test_root=$(mktemp -d)
fake_bin="$test_root/bin"
cache_dir="$test_root/cache"
ssh_config="$test_root/ssh.config"
trap 'rm -f "$output_file"; rm -rf "$test_root"' EXIT HUP INT TERM

expect_failure()
{
  expected_message=$1
  shift

  if "$@" >"$output_file" 2>&1; then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi

  if ! grep -F "$expected_message" "$output_file" >/dev/null; then
    echo "Missing expected failure message: $expected_message" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

expect_failure \
  "set PROFILE=workstation-validation" \
  env PROFILE=invalid ./scripts/lima-lifecycle.sh inventory

expect_failure \
  "set CONFIRM=create-rpr-p1" \
  env PROFILE=workstation-validation CONFIRM= \
  ./scripts/lima-lifecycle.sh up

expect_failure \
  "set CONFIRM=start-rpr-p1" \
  env PROFILE=workstation-validation CONFIRM= \
  ./scripts/lima-lifecycle.sh start

expect_failure \
  "set CONFIRM=delete-rpr-p1" \
  env PROFILE=workstation-validation CONFIRM= \
  ./scripts/lima-lifecycle.sh delete

mkdir -p "$fake_bin"
printf '%s\n' 'Host lima-rpr-p1' >"$ssh_config"

cat >"$fake_bin/limactl" <<EOF
#!/usr/bin/env sh
case "\$1" in
  --version) printf '%s\n' 'limactl version 2.2.0' ;;
  list)
    case "\$3" in
      '{{.Name}}') printf '%s\n' 'rpr-p1' ;;
      '{{.Status}}') printf '%s\n' 'Running' ;;
      '{{.SSHConfigFile}}') printf '%s\n' '$ssh_config' ;;
      *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF

cat >"$fake_bin/ssh" <<'EOF'
#!/usr/bin/env sh
if [ "$1" = "-G" ]; then
  printf '%s\n' 'hostname 127.0.0.1' 'port 60022' 'user lima'
fi
EOF
chmod +x "$fake_bin/limactl" "$fake_bin/ssh"

PATH="$fake_bin:$PATH" \
PROFILE=workstation-validation \
RPR_LIMA_CACHE_DIR="$cache_dir" \
  ./scripts/lima-lifecycle.sh inventory >"$output_file"

jq -e '
  .all.children.incus_hosts.hosts["incus-lima-01"] as $host
  | $host.ansible_host == "lima-rpr-p1"
  and $host.ansible_user == "lima"
  and $host.ansible_port == 60022
  and $host.rpr_controller_ssh_host == "127.0.0.1"
  and $host.debian_prepare_stable_target == true
  and ($host.ansible_ssh_common_args | startswith("-F "))
' "$cache_dir/hosts.json" >/dev/null

echo "Lima lifecycle safety checks passed."
