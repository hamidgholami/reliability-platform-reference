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

## Later targets and revocation

Use a distinct human remote name for a later EC2 target, for example
`rpr-reference`; do not silently replace `rpr-lima`. The isolated `rpr-target`
configuration can be removed and re-enrolled only after verifying the new
server fingerprint.

Removing a local remote does not revoke its server authorization. Before
deleting a disposable target, list its trusted certificates through SSH, match
the certificate name and fingerprint, and remove the intended trust entry. Also
remove any unused pending token. Never delete an entry based only on list
position or a shortened fingerprint.
