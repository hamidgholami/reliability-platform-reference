# DNS and PKI Plan

Status: draft pending domain registration and delegation validation.

## Namespace

The current candidate base domain is `apadanalab.de`.

- `dev.apadanalab.de` — present development and demonstration environment;
- `prod.apadanalab.de` — reserved for a future production-like environment;
- service names are direct and descriptive, for example
  `pulp.dev.apadanalab.de`, `vault.dev.apadanalab.de`, and
  `jenkins.dev.apadanalab.de`.

The redundant form `*.apps.lab.apadanalab.*` is intentionally not used. Domain
and suffix values remain configurable until registration succeeds.

## Cheapest practical external DNS path

1. Register the domain with a reliable registrar that supports the chosen TLD.
2. Delegate authoritative DNS to Cloudflare Free.
3. Enable DNSSEC at Cloudflare and publish the DS record through the registrar.
4. Create a narrowly scoped API token for only the required DNS zone and record
   operations.
5. Use ACME DNS-01 for public certificates without publishing private service
   addresses.

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

Two internal CoreDNS instances serve private answers. Split-horizon records map
service names to Incus addresses locally, while the public zone contains only
safe ownership and challenge records unless a service is deliberately exposed.
