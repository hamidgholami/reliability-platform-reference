#!/usr/bin/env sh
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

set -eu
umask 077

action=${1:-retire}
profile=${PROFILE:-}
config_dir=${INCUS_CONFIG_DIR:-}
remote=${INCUS_REMOTE:-}
inventory=${OPENBAO_INVENTORY:-"$PWD/.cache/incus-substrate/openbao-hosts.json"}
pki_dir=${RPR_PKI_DIR:-}
recovery_dir=${OPENBAO_RECOVERY_DIR:-${RPR_PKI_DIR:+$RPR_PKI_DIR/openbao-recovery}}
runtime_dir=${OPENBAO_RUNTIME_DIR:-${RPR_PKI_DIR:+$RPR_PKI_DIR/openbao-runtime}}
client_dir=${RPR_PKI_DIR:+$RPR_PKI_DIR/openbao-root-generation}
gpg_home=
root_token_file=
client_key_file=
helper_result_file=
private_public_file=
certificate_public_file=
recovery_passphrase=
entered_input=
echo_disabled=0
remote_material_installed=0
remote_prefix=/run/rpr-openbao-root-retirement
if [ "$action" = "p203-machine-auth" ]; then
  remote_prefix=/run/rpr-openbao-p203-session
elif [ "$action" = "p203-postgresql" ]; then
  remote_prefix=/run/rpr-openbao-p203-db
elif [ "$action" = "p203-ssh-certificates" ]; then
  remote_prefix=/run/rpr-openbao-p203-ssh
fi

fail()
{
  echo "Error: $*" >&2
  exit 1
}

restore_terminal()
{
  if [ "$echo_disabled" -eq 1 ]; then
    stty echo >/dev/null 2>&1 || true
    printf '\n' >&2
    echo_disabled=0
  fi
}

incus_exec()
{
  INCUS_CONF="$config_dir" \
    incus exec --project rpr-dev "$remote:bao-01" -- "$@"
}

postgresql_exec()
{
  INCUS_CONF="$config_dir" \
    incus exec --project rpr-dev "$remote:pg-01" -- "$@"
}

cleanup()
{
  restore_terminal
  recovery_passphrase=
  entered_input=
  if [ "$remote_material_installed" -eq 1 ]; then
    incus_exec rm -f \
      "$remote_prefix.py" \
      "$remote_prefix-client.crt" \
      "$remote_prefix-client.key" \
      "$remote_prefix-machine.crt" \
      "$remote_prefix-pg.csr" \
      "$remote_prefix-pg.crt" \
      "$remote_prefix-pg-password" \
      "$remote_prefix-initial-token" >/dev/null 2>&1 || true
  fi
  if [ "$action" = "p203-postgresql" ]; then
    postgresql_exec rm -f \
      /run/rpr-postgresql-bootstrap/admin-password \
      /run/rpr-postgresql-bootstrap/tls.crt \
      /run/rpr-postgresql-bootstrap/ca.crt >/dev/null 2>&1 || true
  fi
  for temporary_file in \
    "$root_token_file" \
    "$client_key_file" \
    "$helper_result_file" \
    "$private_public_file" \
    "$certificate_public_file"; do
    if [ -n "$temporary_file" ] && [ -f "$temporary_file" ]; then
      rm -f "$temporary_file"
    fi
  done
  if [ -n "$gpg_home" ] && [ -d "$gpg_home" ]; then
    gpgconf --homedir "$gpg_home" --kill gpg-agent >/dev/null 2>&1 || true
    rm -rf "$gpg_home"
  fi
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

read_secret()
{
  printf '%s' "OpenBao recovery-key passphrase: " >&2
  if [ -t 0 ]; then
    stty -echo
    echo_disabled=1
  fi
  if ! IFS= read -r entered_input; then
    restore_terminal
    fail "could not read the recovery-key passphrase"
  fi
  restore_terminal
  recovery_passphrase=$entered_input
  entered_input=
  [ "${#recovery_passphrase}" -ge 16 ] ||
    fail "the recovery-key passphrase must contain at least 16 characters"
}

gpg_with_passphrase()
{
  gpg \
    --homedir "$gpg_home" \
    --batch \
    --quiet \
    --pinentry-mode loopback \
    --passphrase-fd 3 \
    "$@" 3<<EOF
$recovery_passphrase
EOF
}

case "$action" in
  retire|p203-machine-auth|p203-postgresql|p203-ssh-certificates) ;;
  *) fail "usage: $0 {retire|p203-machine-auth|p203-postgresql|p203-ssh-certificates}" ;;
esac
case "$profile" in
  workstation-validation|single-node-reference) ;;
  *) fail "set PROFILE to workstation-validation or single-node-reference" ;;
esac
case "$config_dir" in
  /*) ;;
  *) fail "INCUS_CONFIG_DIR must be an absolute path" ;;
esac
[ -n "$remote" ] || fail "set INCUS_REMOTE to the pre-enrolled remote name"
case "$remote" in
  *[!A-Za-z0-9_.-]*|'') fail "INCUS_REMOTE contains unsupported characters" ;;
esac
case "$pki_dir" in
  /*) ;;
  *) fail "RPR_PKI_DIR must be an absolute protected directory" ;;
esac
case "$recovery_dir" in
  /*) ;;
  *) fail "OPENBAO_RECOVERY_DIR must be an absolute protected directory" ;;
esac
case "$runtime_dir" in
  /*) ;;
  *) fail "OPENBAO_RUNTIME_DIR must be an absolute protected directory" ;;
esac

repo_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
for protected_dir in "$recovery_dir" "$runtime_dir" "$client_dir"; do
  case "$protected_dir" in
    "$repo_dir"|"$repo_dir"/*)
      fail "OpenBao protected directories must remain outside the repository"
      ;;
  esac
done

case "$action" in
  retire) expected="retire-openbao-root-token-$profile-$remote" ;;
  p203-machine-auth) expected="configure-machine-auth-$profile-$remote" ;;
  p203-postgresql) expected="enable-postgresql-dynamic-$profile-$remote" ;;
  p203-ssh-certificates) expected="configure-ssh-certificates-$profile-$remote" ;;
esac
[ "${CONFIRM:-}" = "$expected" ] || fail "set CONFIRM=$expected"
[ -r "$inventory" ] || fail "OpenBao inventory is missing; run make apply"
[ -r "$recovery_dir/recovery-secret.gpg" ] ||
  fail "the protected recovery secret key is missing"
[ -r "$recovery_dir/initialization.json" ] ||
  fail "the encrypted initialization response is missing"
[ "$(find "$recovery_dir" -prune -type d -perm 0700 -print)" = "$recovery_dir" ] ||
  fail "OPENBAO_RECOVERY_DIR must use mode 0700"
for protected_file in recovery-secret.gpg initialization.json; do
  protected_path="$recovery_dir/$protected_file"
  [ "$(find "$protected_path" -prune -type f -perm 0600 -print)" = "$protected_path" ] ||
    fail "$protected_file must use mode 0600"
done
if [ "$action" = "retire" ]; then
  jq -e '
    (.unseal_keys_b64 | length) == 1
    and (.unseal_keys_b64[0] | type) == "string"
    and (.unseal_keys_b64[0] | length) > 0
    and (.root_token | type) == "string"
    and (.root_token | length) > 0
  ' "$recovery_dir/initialization.json" >/dev/null ||
    fail "the initial root token is absent or already retired"
else
  jq -e '
    (.unseal_keys_b64 | length) == 1
    and (.unseal_keys_b64[0] | type) == "string"
    and (.unseal_keys_b64[0] | length) > 0
    and (has("root_token") | not)
  ' "$recovery_dir/initialization.json" >/dev/null ||
    fail "the protected recovery bundle is not in the retired-root state"
fi

for tool in gpg gpgconf incus jq openssl python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done
[ -x .venv/bin/ansible-playbook ] || fail "run make setup-python first"

jq -e \
  --arg profile "$profile" \
  --arg remote "$remote" '
    .all.children.openbao_service as $bao
    | $bao.vars.rpr_deployment_profile == $profile
    and $bao.vars.ansible_incus_remote == $remote
    and $bao.vars.ansible_incus_project == "rpr-dev"
    and $bao.vars.openbao_platform_cidr == "10.20.0.0/24"
    and $bao.vars.openbao_api_address == "10.20.0.20"
    and $bao.vars.openbao_api_port == 8200
    and $bao.vars.openbao_api_dns_name == "openbao.dev.apadanalab.de"
    and ($bao.hosts | keys) == ["bao-01"]
    and $bao.hosts["bao-01"].ansible_host == "bao-01"
  ' "$inventory" >/dev/null || fail "OpenBao inventory violates the reviewed boundary"

if [ "$action" != "retire" ]; then
  jq -e --arg profile "$profile" --arg remote "$remote" '
    .all.children.machine_auth_client as $machine
    | $machine.vars.rpr_deployment_profile == $profile
    and $machine.vars.ansible_incus_remote == $remote
    and $machine.vars.ansible_incus_project == "rpr-dev"
    and ($machine.hosts | keys) == ["smoke-01"]
    and $machine.hosts["smoke-01"].ansible_host == "smoke-01"
  ' "$inventory" >/dev/null ||
  fail "machine-auth inventory is missing or invalid; run make validate"
fi

if [ "$action" = "p203-ssh-certificates" ]; then
  jq -e --arg profile "$profile" --arg remote "$remote" '
    .all.children.ssh_test_target as $target
    | $target.vars.rpr_deployment_profile == $profile
    and $target.vars.ansible_incus_remote == $remote
    and $target.vars.ansible_incus_project == "rpr-dev"
    and ($target.hosts | keys) == ["ssh-test-01"]
    and $target.hosts["ssh-test-01"].ansible_host == "ssh-test-01"
    and $target.vars.ssh_test_private_address == "10.20.0.221"
  ' "$inventory" >/dev/null ||
    fail "SSH test inventory is missing or invalid; run make validate"
fi

if [ "$action" != "retire" ]; then
  incus_exec curl -fsS \
    --cacert /opt/openbao/tls/ca.crt \
    https://10.20.0.20:8200/v1/sys/health >/dev/null 2>&1 ||
    fail "OpenBao is not ready or is sealed; run make openbao-status and make unseal-openbao"
  if [ "$action" = "p203-machine-auth" ]; then
    echo "Preparing the Ed25519 machine credential inside smoke-01..."
    INCUS_CONF="$config_dir" \
    ANSIBLE_CONFIG="$PWD/ansible.cfg" \
    ANSIBLE_HOME="$PWD/.cache/ansible" \
    ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
    ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
    .venv/bin/ansible-playbook \
      --diff --tags prepare --inventory "$inventory" \
      ansible/playbooks/configure-machine-auth.yml
  elif [ "$action" = "p203-postgresql" ]; then
    jq -e --arg profile "$profile" --arg remote "$remote" '
      .all.children.postgresql_service as $pg
      | $pg.vars.rpr_deployment_profile == $profile
      and $pg.vars.ansible_incus_remote == $remote
      and $pg.vars.ansible_incus_project == "rpr-dev"
      and ($pg.hosts | keys) == ["pg-01"]
      and $pg.hosts["pg-01"].ansible_host == "pg-01"
      and $pg.vars.postgresql_private_address == "10.20.0.21"
      and $pg.vars.postgresql_openbao_address == "10.20.0.20"
    ' "$inventory" >/dev/null ||
      fail "PostgreSQL inventory is missing or invalid; run make validate"
    echo "Preparing the PostgreSQL key, CSR, and one-use admin password inside pg-01..."
    INCUS_CONF="$config_dir" \
    ANSIBLE_CONFIG="$PWD/ansible.cfg" \
    ANSIBLE_HOME="$PWD/.cache/ansible" \
    ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
    ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
    .venv/bin/ansible-playbook \
      --diff --tags prepare --inventory "$inventory" \
      ansible/playbooks/enable-postgresql-dynamic.yml
  fi
fi

install -d -m 0700 "$runtime_dir"
if [ -e "$client_dir" ] && [ ! -d "$client_dir" ]; then
  fail "the root-generation client path exists but is not a directory"
fi
install -d -m 0700 "$client_dir"
[ "$(find "$client_dir" -prune -type d -perm 0700 -print)" = "$client_dir" ] ||
  fail "the root-generation client directory must use mode 0700"

gpg_home=$(mktemp -d /tmp/rpr-openbao-gpg.XXXXXX)
gpgconf --homedir "$gpg_home" --launch gpg-agent
gpg --homedir "$gpg_home" --batch --quiet \
  --import "$recovery_dir/recovery-secret.gpg"
recovery_fingerprint=$(gpg \
  --homedir "$gpg_home" \
  --batch --with-colons --list-secret-keys |
  awk -F: '$1 == "fpr" { print $10; exit }')
[ -n "$recovery_fingerprint" ] || fail "could not identify the recovery key"
read_secret

if [ "$action" = "retire" ]; then
  root_token_file=$(mktemp "$runtime_dir/initial-root-token.XXXXXX")
  jq -er '.root_token' "$recovery_dir/initialization.json" |
    openssl base64 -d -A |
    gpg_with_passphrase --decrypt >"$root_token_file" ||
    fail "the encrypted initial root token could not be recovered"
  chmod 0600 "$root_token_file"
  [ -s "$root_token_file" ] || fail "the recovered initial root token is empty"
fi

client_key_file=$(mktemp "$runtime_dir/root-generation-client-key.XXXXXX")
if [ "$action" = "retire" ] &&
  [ ! -e "$client_dir/client.crt" ] && [ ! -e "$client_dir/client.key.gpg" ]; then
  echo "Creating the exact-pinned root-generation client credential..."
  openssl genpkey \
    -algorithm RSA \
    -pkeyopt rsa_keygen_bits:3072 \
    -out "$client_key_file" >/dev/null 2>&1 ||
    fail "could not generate the root-generation client key"
  openssl req \
    -new \
    -x509 \
    -sha256 \
    -days 1825 \
    -key "$client_key_file" \
    -out "$client_dir/client.crt" \
    -subj '/O=ApadanaLab/OU=Platform Recovery/CN=RPR OpenBao Root Generation' \
    -addext 'basicConstraints=critical,CA:FALSE' \
    -addext 'keyUsage=critical,digitalSignature' \
    -addext 'extendedKeyUsage=clientAuth' ||
    fail "could not create the root-generation client certificate"
  gpg \
    --homedir "$gpg_home" \
    --batch \
    --quiet \
    --trust-model always \
    --recipient "$recovery_fingerprint" \
    --output "$client_dir/client.key.gpg" \
    --encrypt "$client_key_file" ||
    fail "could not encrypt the root-generation client key"
  chmod 0600 "$client_dir/client.crt" "$client_dir/client.key.gpg"
elif [ -r "$client_dir/client.crt" ] && [ -r "$client_dir/client.key.gpg" ]; then
  gpg_with_passphrase --decrypt "$client_dir/client.key.gpg" >"$client_key_file" ||
    fail "the encrypted root-generation client key could not be recovered"
else
  fail "the root-generation client artifacts are incomplete"
fi
chmod 0600 "$client_key_file"

for protected_file in client.crt client.key.gpg; do
  protected_path="$client_dir/$protected_file"
  [ "$(find "$protected_path" -prune -type f -perm 0600 -print)" = "$protected_path" ] ||
    fail "$protected_file must use mode 0600"
done
openssl verify -CAfile "$client_dir/client.crt" "$client_dir/client.crt" >/dev/null ||
  fail "the root-generation client certificate is not self-consistent"
openssl x509 -in "$client_dir/client.crt" -noout -checkend 126144000 >/dev/null ||
  fail "the root-generation client certificate has less than four years remaining"
client_subject=$(openssl x509 \
  -in "$client_dir/client.crt" -noout -subject -nameopt RFC2253)
[ "$client_subject" = \
  'subject=CN=RPR OpenBao Root Generation,OU=Platform Recovery,O=ApadanaLab' ] ||
  fail "the root-generation client certificate has an unexpected subject"
openssl x509 -in "$client_dir/client.crt" -noout -purpose |
  grep -F 'SSL client : Yes' >/dev/null ||
  fail "the root-generation client certificate lacks client authentication"
private_public_file=$(mktemp "$runtime_dir/root-generation-private-public.XXXXXX")
certificate_public_file=$(mktemp "$runtime_dir/root-generation-certificate-public.XXXXXX")
openssl pkey -in "$client_key_file" -pubout >"$private_public_file"
openssl x509 -in "$client_dir/client.crt" -pubkey -noout >"$certificate_public_file"
cmp -s "$private_public_file" "$certificate_public_file" ||
  fail "the root-generation client certificate does not match its encrypted key"
rm -f "$private_public_file" "$certificate_public_file"
private_public_file=
certificate_public_file=

if [ "$action" = "retire" ]; then
  export OPENBAO_ROOT_TOKEN_FILE="$root_token_file"
  export OPENBAO_ROOT_RECOVERY_CLIENT_DIR="$client_dir"
  echo "Configuring authenticated root generation: profile=$profile remote=$remote"
  INCUS_CONF="$config_dir" \
  ANSIBLE_CONFIG="$PWD/ansible.cfg" \
  ANSIBLE_HOME="$PWD/.cache/ansible" \
  ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
  ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
  .venv/bin/ansible-playbook \
    --diff \
    --inventory "$inventory" \
    ansible/playbooks/configure-openbao-root-recovery.yml
fi

incus_exec sh -c \
  "umask 077; cat > '$remote_prefix.py'; chmod 0700 '$remote_prefix.py'" \
  <"$repo_dir/scripts/openbao-root-retirement-remote.py"
remote_material_installed=1
incus_exec sh -c \
  "umask 077; cat > '$remote_prefix-client.crt'" \
  <"$client_dir/client.crt"
incus_exec sh -c \
  "umask 077; cat > '$remote_prefix-client.key'" \
  <"$client_key_file"
if [ "$action" = "retire" ]; then
  incus_exec sh -c \
    "umask 077; cat > '$remote_prefix-initial-token'" \
    <"$root_token_file"
else
  if [ "$action" = "p203-machine-auth" ]; then
    INCUS_CONF="$config_dir" \
      incus exec --project rpr-dev "$remote:smoke-01" -- \
        cat /etc/rpr-machine-auth/client.crt |
      incus_exec sh -c \
        "umask 077; cat > '$remote_prefix-machine.crt'" ||
      fail "could not transfer the public machine certificate"
  elif [ "$action" = "p203-postgresql" ]; then
    postgresql_exec cat /run/rpr-postgresql-bootstrap/tls.csr |
      incus_exec sh -c \
        "umask 077; cat > '$remote_prefix-pg.csr'" ||
      fail "could not transfer the public PostgreSQL CSR"
    postgresql_exec cat /run/rpr-postgresql-bootstrap/admin-password |
      incus_exec sh -c \
        "umask 077; cat > '$remote_prefix-pg-password'" ||
      fail "could not transfer the protected PostgreSQL admin password"
  fi
fi

if [ "$action" = "p203-machine-auth" ]; then
  helper_result_file=$(mktemp "$runtime_dir/p203-machine-result.XXXXXX")
  echo "Configuring the exact-pinned machine identity through authenticated recovery..."
  jq -er '.unseal_keys_b64[0]' "$recovery_dir/initialization.json" |
    openssl base64 -d -A |
    gpg_with_passphrase --decrypt |
    incus_exec python3 \
      "$remote_prefix.py" \
      "$remote_prefix-client.crt" \
      "$remote_prefix-client.key" \
      --machine-auth \
      "$remote_prefix-machine.crt" >"$helper_result_file" ||
    fail "authenticated P2-03 recovery failed"
  jq -e '.machine_auth_configured and .temporary_root_revoked' \
    "$helper_result_file" >/dev/null ||
    fail "machine-auth recovery did not report a completed root-token revocation"
  echo "Proving certificate login and exact machine capabilities..."
  INCUS_CONF="$config_dir" \
  ANSIBLE_CONFIG="$PWD/ansible.cfg" \
  ANSIBLE_HOME="$PWD/.cache/ansible" \
  ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
  ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
  .venv/bin/ansible-playbook \
    --diff --tags accept --inventory "$inventory" \
    ansible/playbooks/configure-machine-auth.yml
  exit 0
fi

if [ "$action" = "p203-postgresql" ]; then
  helper_result_file=$(mktemp "$runtime_dir/p203-postgresql-result.XXXXXX")
  echo "Signing PostgreSQL TLS and configuring the bounded database engine through authenticated recovery..."
  jq -er '.unseal_keys_b64[0]' "$recovery_dir/initialization.json" |
    openssl base64 -d -A |
    gpg_with_passphrase --decrypt |
    incus_exec python3 \
      "$remote_prefix.py" \
      "$remote_prefix-client.crt" \
      "$remote_prefix-client.key" \
      --postgresql \
      "$remote_prefix-pg.csr" \
      "$remote_prefix-pg-password" >"$helper_result_file" ||
    fail "authenticated PostgreSQL recovery failed"
  jq -e '.postgresql_configured and .temporary_root_revoked' \
    "$helper_result_file" >/dev/null ||
    fail "PostgreSQL recovery did not report completed root-token revocation"
  incus_exec cat "$remote_prefix-pg.crt" |
    postgresql_exec sh -c \
      'umask 077; cat > /run/rpr-postgresql-bootstrap/tls.crt' ||
    fail "could not transfer the signed PostgreSQL certificate"
  incus_exec cat /opt/openbao/tls/ca.crt |
    postgresql_exec sh -c \
      'umask 077; cat > /run/rpr-postgresql-bootstrap/ca.crt' ||
    fail "could not transfer the public CA bundle"
  echo "Activating the private PostgreSQL TLS listener and peer restrictions..."
  INCUS_CONF="$config_dir" \
  ANSIBLE_CONFIG="$PWD/ansible.cfg" \
  ANSIBLE_HOME="$PWD/.cache/ansible" \
  ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
  ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
  .venv/bin/ansible-playbook \
    --diff --tags activate --inventory "$inventory" \
    ansible/playbooks/enable-postgresql-dynamic.yml
  exit 0
fi

if [ "$action" = "p203-ssh-certificates" ]; then
  helper_result_file=$(mktemp "$runtime_dir/p203-ssh-result.XXXXXX")
  echo "Configuring the Ed25519 SSH client CA through authenticated recovery..."
  jq -er '.unseal_keys_b64[0]' "$recovery_dir/initialization.json" |
    openssl base64 -d -A |
    gpg_with_passphrase --decrypt |
    incus_exec python3 \
      "$remote_prefix.py" \
      "$remote_prefix-client.crt" \
      "$remote_prefix-client.key" \
      --ssh-certificates >"$helper_result_file" ||
    fail "authenticated SSH CA recovery failed"
  jq -e '.ssh_certificates_configured and .temporary_root_revoked' \
    "$helper_result_file" >/dev/null ||
    fail "SSH CA recovery did not report completed root-token revocation"
  echo "Configuring the disposable Ed25519 SSH target..."
  INCUS_CONF="$config_dir" \
  ANSIBLE_CONFIG="$PWD/ansible.cfg" \
  ANSIBLE_HOME="$PWD/.cache/ansible" \
  ANSIBLE_COLLECTIONS_PATH="$PWD/.cache/ansible/collections" \
  ANSIBLE_LOCAL_TEMP="$PWD/.cache/ansible/tmp" \
  .venv/bin/ansible-playbook \
    --diff --inventory "$inventory" \
    ansible/playbooks/configure-ssh-test.yml
  exit 0
fi

helper_result_file=$(mktemp "$runtime_dir/root-retirement-result.XXXXXX")
echo "Generating and revoking a recovery root before retiring the initial token..."
jq -er '.unseal_keys_b64[0]' "$recovery_dir/initialization.json" |
  openssl base64 -d -A |
  gpg_with_passphrase --decrypt |
  incus_exec python3 \
    "$remote_prefix.py" \
    "$remote_prefix-client.crt" \
    "$remote_prefix-client.key" \
    "$remote_prefix-initial-token" >"$helper_result_file" ||
  fail "the OpenBao root-retirement ceremony failed"

jq -e '
  .authenticated_recovery == true
  and .temporary_root_generated == true
  and .bounded_admin_proven == true
  and .temporary_root_revoked == true
  and .initial_root_revoked == true
  and .recovery_session_revoked == true
' "$helper_result_file" >/dev/null ||
  fail "the OpenBao root-retirement result is invalid"

retired_initialization=$(mktemp "$recovery_dir/.initialization.retired.XXXXXX")
jq 'del(.root_token)' "$recovery_dir/initialization.json" >"$retired_initialization"
chmod 0600 "$retired_initialization"
mv "$retired_initialization" "$recovery_dir/initialization.json"
jq -e '
  (has("root_token") | not)
  and (.unseal_keys_b64 | length) == 1
  and (.unseal_keys_b64[0] | type) == "string"
' "$recovery_dir/initialization.json" >/dev/null ||
  fail "the retired recovery bundle is invalid"

recovery_passphrase=
echo "Authenticated root recovery was proven and every temporary token was revoked."
echo "The initial root token was revoked and removed from the protected recovery bundle."
