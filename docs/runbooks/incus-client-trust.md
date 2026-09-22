<!--
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
-->

# Incus client and provider trust

P1-05 establishes two TLS client identities before OpenTofu owns any Incus
resource. The normal MacBook client identity belongs to the human operator. A
second identity under the ignored `.cache/incus/opentofu` directory belongs
only to OpenTofu. Do not reuse either private key for SSH or another service.

The trust contract is designed for the remote `single-node-reference` target.
The Lima commands below exercise it cheaply through a loopback forward, but
they are an optional rehearsal rather than the deployment definition. A later
reference run supplies its reviewed endpoint and fingerprint without changing
the shared provider configuration.

An Incus administrator certificate is equivalent to root-level control of the
host. Keep both private keys local, never commit their configuration directory,
and revoke server trust when a disposable environment is removed. Later
identity and authorization phases may narrow access, but the bootstrap identity
must initially create and destroy the development project itself.

## Verify the server certificate

For the current Lima target, print the independently recorded server
fingerprint:

```sh
jq -r '.server_certificate_sha256' reports/p1-03/incus-lima-01.json
```

The value shown by `incus remote add` must match this fingerprint. Stop if it
does not. Do not use `--accept-certificate`; confirmation is a deliberate human
trust decision.

## Enroll the human operator

Generate a one-time token through the already authenticated SSH path:

```sh
ssh -F ~/.lima/rpr-p1/ssh.config lima-rpr-p1 \
  'sudo incus config trust add rpr-mac-operator -q'
```

Treat the output as a secret. Immediately run the following command, confirm
the independently recorded server fingerprint, and paste the token only when
the client prompts for it:

```sh
incus remote add rpr-lima https://127.0.0.1:18443
```

Do not switch the default remote. Qualifying the remote keeps inspection
explicit and reduces accidental mutations:

```sh
incus info rpr-lima:
incus list rpr-lima:
incus operation list rpr-lima:
```

The operator may inspect and troubleshoot with this client. Routine lifecycle
changes to provider-owned resources must still go through OpenTofu.

## Enroll the OpenTofu identity

Prepare its isolated, ignored configuration directory:

```sh
mkdir -p "$PWD/.cache/incus/opentofu"
chmod 700 "$PWD/.cache/incus/opentofu"
```

Generate a different one-time token:

```sh
ssh -F ~/.lima/rpr-p1/ssh.config lima-rpr-p1 \
  'sudo incus config trust add rpr-opentofu -q'
```

Then enroll the isolated client. As before, compare the fingerprint and paste
the token only at the interactive prompt:

```sh
INCUS_CONF="$PWD/.cache/incus/opentofu" \
  incus remote add rpr-target https://127.0.0.1:18443
```

Export the non-secret trust inputs for the repository wrappers:

```sh
export PROFILE=workstation-validation
export INCUS_CONFIG_DIR="$PWD/.cache/incus/opentofu"
export INCUS_REMOTE=rpr-target
export INCUS_ENDPOINT=https://127.0.0.1:18443
export INCUS_SERVER_CERTIFICATE_SHA256="$(
  jq -r '.server_certificate_sha256' reports/p1-03/incus-lima-01.json
)"
```

Verify the client boundary and produce a provider plan:

```sh
make incus-client-check
make plan
```

The check requires a matching pinned server certificate, a matching client
certificate and key, trusted API access, and a standalone server. The provider
loads the pre-enrolled remote from the isolated configuration directory with
automatic certificate generation and server-certificate acceptance explicitly
disabled. Neither command creates a resource. Review and apply the resulting
plan through the [Incus substrate lifecycle](incus-substrate.md). The saved
plan, runtime inputs, session metadata, and state stay under ignored `.cache`
paths with operator-only permissions.

## Reference-VM enrollment

Keep the reference VM separate from the preserved Lima environment. Use a
distinct human remote, isolated OpenTofu client directory, provider remote, and
provider state directory:

```sh
export PROFILE=single-node-reference
export INVENTORY="$PWD/.cache/aws-single-node/hosts.json"
export TARGET_HOST=incus-reference-01
export RPR_REFERENCE_IP="$(
  jq -r '.all.children.incus_hosts.hosts["incus-reference-01"].ansible_host' \
    "$INVENTORY"
)"
export INCUS_ENDPOINT="https://${RPR_REFERENCE_IP}:8443"
export INCUS_CONFIG_DIR="$PWD/.cache/incus/reference-opentofu"
export INCUS_REMOTE=rpr-reference-tofu
export RPR_INCUS_CACHE_DIR="$PWD/.cache/incus-substrate-reference"
export INCUS_SERVER_CERTIFICATE_SHA256="$(
  jq -r '.server_certificate_sha256' reports/p1-03/incus-reference-01.json
)"
```

The AWS security group exposes the Incus API only to the reviewed operator
IPv4 `/32`. Incus still requires a trusted TLS client certificate; network
reachability alone grants no API access. Compare the server fingerprint with
`INCUS_SERVER_CERTIFICATE_SHA256` during both enrollments and stop on any
mismatch.

Create and enroll the human operator identity first:

```sh
ssh admin@"$RPR_REFERENCE_IP" \
  'incus config trust add rpr-mac-reference -q'

incus remote add rpr-reference "$INCUS_ENDPOINT"
```

Treat the first command's token as a secret and paste it only into the second
command's prompt. Keep `rpr-lima` configured; do not change the default remote.

Create the isolated OpenTofu identity independently:

```sh
mkdir -p "$INCUS_CONFIG_DIR"
chmod 700 "$INCUS_CONFIG_DIR"

ssh admin@"$RPR_REFERENCE_IP" \
  'incus config trust add rpr-opentofu-reference -q'

INCUS_CONF="$INCUS_CONFIG_DIR" \
  incus remote add "$INCUS_REMOTE" "$INCUS_ENDPOINT"
```

Verify both paths before planning resources:

```sh
incus info rpr-reference:
make incus-client-check
make plan
```

The reference-specific `RPR_INCUS_CACHE_DIR` is mandatory for this milestone.
It prevents the reference plan, state, inventory, and evidence from replacing
the corresponding Lima files.

## Revocation and local cleanup

Removing a local remote does not revoke its server authorization. Before
deleting a disposable target, list its trusted certificates through SSH, match
the two reference certificate names and full fingerprints, and remove those
entries. Also remove any unused pending token. Never delete an entry based only
on list position or a shortened fingerprint.

After provider destroy succeeds and trust is revoked, remove the human and
isolated client remotes:

```sh
incus remote remove rpr-reference
INCUS_CONF="$INCUS_CONFIG_DIR" incus remote remove "$INCUS_REMOTE"
```

Delete the ignored reference client and provider cache directories only after
the final evidence is recorded and the AWS target has been destroyed. This
cleanup does not affect the separate Lima client or substrate state.
