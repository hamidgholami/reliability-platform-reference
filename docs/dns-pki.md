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

The internal DNS design is documented in
[ADR-0003](adr/0003-separate-platform-and-kubernetes-dns-roles.md). Incus
network zones are the hidden primary and generate records from Incus state. Two
BIND 9 secondaries receive those zones through authenticated transfer and serve
private authoritative answers. Kubernetes retains CoreDNS for cluster service
discovery and forwards the platform namespace to BIND. Split-horizon records
map service names to Incus addresses locally, while the public zone contains
only safe ownership and challenge records unless a service is deliberately
exposed.

Public DNS must never contain RFC 1918 service addresses.

## Private record workflow

Git contains the desired Incus network, instance, and zone configuration. Incus
automatically generates DNS records for instances attached to the zone, so
those addresses are not duplicated in a hand-written BIND zone.

Future Git-tracked provider inputs are the source of truth only for manual
records outside Kubernetes. These include service aliases, names that do not
match an Incus instance, and addresses not derived from the attached Incus
network. An `A` record maps a name to an address, while a `CNAME` maps an alias
to another DNS name and never directly to an IP address.

The change flow is:

1. The official Incus provider declares the forward/reverse zones, their
   network attachment, approved BIND transfer peers, and reviewed manual
   records.
2. Incus automatically generates records when instances, gateways, and network
   ports change.
3. For a manual name or alias, add the desired record to the Git-tracked
   provider inputs and apply it through the Incus API.
4. CI validates the data and BIND secondary configuration.
5. Incus notifies both BIND secondaries, which retrieve the updated zone through
   authenticated AXFR and answer normal DNS queries.
6. Incus managed-bridge DNS and Kubernetes CoreDNS conditionally forward
   `dev.apadanalab.de` queries to the BIND pair.
7. Trusted workstations, VPN clients, and future site resolvers use the same
   split-DNS route.

This Git-and-review workflow replaces a DNS web portal in the baseline. A later
self-service interface may create reviewed changes through the same source of
truth, but it must not edit transferred BIND data or update Incus behind Git and
introduce configuration drift.

## Private service certificates

A private service can still present a verified certificate without a public IP:

- the default is a certificate from the internal CA, with its root distributed
  to trusted clients through the operator trust kit;
- when a publicly trusted certificate is justified, ACME DNS-01 creates only a
  public TXT challenge record at Netcup. The service's private `A` record remains
  in the Incus/BIND private DNS path and is never published at Netcup.

Publicly trusted certificate names may appear in certificate-transparency logs,
so internal certificates remain preferable for names that should not be
disclosed.
