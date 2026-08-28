# DNS and PKI Plan

Status: Phase 0 baseline; DNSSEC and certificate automation remain to be
implemented.

## Namespace

The registered base domain is `apadanalab.de`.

- `dev.apadanalab.de` — present development and demonstration environment;
- `prod.apadanalab.de` — reserved for a future production-like environment;
- service names are direct and descriptive, for example
  `pulp.dev.apadanalab.de`, `vault.dev.apadanalab.de`, and
  `jenkins.dev.apadanalab.de`.

The redundant form `*.apps.lab.apadanalab.*` is intentionally not used. Domain
and suffix values remain configurable so profiles can be reproduced elsewhere.

## Public authoritative DNS

Netcup is the registrar and authoritative DNS provider. The live delegation is
to Netcup nameservers, so another DNS provider is not required. The next steps
are to enable DNSSEC through Netcup and validate the resulting DS chain.

Cloudflare is not part of the baseline. It may be reconsidered only if a later
requirement justifies moving public authoritative DNS, such as a needed proxy,
WAF, or a materially safer certificate-automation interface.

ACME DNS-01 automation must use a maintained client or integration that supports
the Netcup API. Provider credentials must be scoped as narrowly as Netcup
allows, stored in Vault/OpenBao, and excluded from Git. If direct automation
cannot meet that security contract, delegate only the ACME challenge namespace
to a suitable automation provider rather than moving the entire public zone.

Registrar lock, account MFA, recovery codes, and separate recovery contacts are
part of the trust boundary.

## Certificate model

- Publicly reachable endpoints use ACME-issued certificates after DNS control is
  proven.
- Private services use an internal CA whose root is distributed explicitly to
  trusted clients.
- Ad-hoc self-signed leaf certificates are allowed only during bootstrap and
  must have a removal date.
- CA private keys, ACME credentials, and recovery material never enter Git.

The proposed internal DNS design is documented in
[ADR-0003](adr/0003-separate-platform-and-kubernetes-dns-roles.md). Two BIND 9
instances serve private authoritative answers for the platform namespace.
Kubernetes retains CoreDNS for cluster service discovery and forwards the
platform namespace to BIND. Split-horizon records map service names to Incus
addresses locally, while the public zone contains only safe ownership and
challenge records unless a service is deliberately exposed.

Public DNS must never contain RFC 1918 service addresses.
