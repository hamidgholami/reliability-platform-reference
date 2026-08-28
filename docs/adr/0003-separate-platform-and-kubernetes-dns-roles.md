# ADR-0003: Separate platform and Kubernetes DNS roles

- Status: proposed
- Date: 2026-08-28
- Decider: Hamid Gholami

## Context

The platform needs private authoritative records for services on Incus as well
as Kubernetes-native service discovery. Using CoreDNS for both roles would keep
the product list small, but it would blur two operational boundaries and provide
less experience with conventional authoritative DNS administration.

The registered public domain is already delegated to Netcup. Public DNS hosting
and private platform DNS are separate concerns: the public zone must not reveal
private service addresses.

## Proposed decision

Use Netcup for public authoritative DNS. Run a primary and secondary BIND 9
service on foundational Incus instances for the private platform namespace.
Keep CoreDNS inside Kubernetes for `cluster.local` service discovery and forward
queries for the private platform namespace to BIND.

Manage the private zone, access controls, forwarding, transfers, and validation
through the platform's Ansible automation. Do not expose the private BIND
instances publicly.

## Rationale

BIND 9 is a better fit for demonstrating traditional authoritative DNS
operations, including primary/secondary topology, authenticated zone transfer,
dynamic update, views, and DNSSEC concepts. CoreDNS remains the natural
Kubernetes DNS component because its Kubernetes plugin discovers Services and
Pods directly.

The split adds one product but gives each server a narrow role. It also keeps
private name resolution available while the workload cluster is unavailable.

## Consequences

- BIND configuration, zone serials, transfers, monitoring, and recovery need
  their own automation and tests.
- Kubernetes DNS depends on the BIND pair only for platform names, not for
  cluster-local service discovery.
- Clients outside Kubernetes use the platform resolvers and receive private
  split-horizon answers.
- Netcup remains sufficient for public DNS; Cloudflare is optional rather than
  architectural.

## Alternatives considered

- Use CoreDNS everywhere: simpler and lightweight, but provides less depth for
  authoritative infrastructure DNS and combines distinct operational roles.
- Use BIND inside Kubernetes too: rejected because Kubernetes-native service
  discovery is already handled well by CoreDNS.
- Delegate public DNS to Cloudflare: unnecessary for the current requirements;
  reconsider only if its automation, proxy, or security services become a
  justified dependency.

## Validation and reversal

Before accepting this ADR, verify that two BIND instances can answer the private
zone, transfer changes securely, survive either instance being unavailable,
forward external queries, and resolve correctly through Kubernetes CoreDNS.
Reverse the choice with a superseding ADR if its operational cost is not
justified by the demonstrated capability.

## References

- [BIND 9 Administrator Reference Manual](https://bind9.readthedocs.io/en/latest/)
- [CoreDNS manual](https://coredns.io/manual/toc/)
- [Kubernetes DNS customization](https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/)
- [Netcup domain documentation](https://www.netcup.com/en/helpcenter/documentation/domain)
- [cert-manager Cloudflare DNS-01 integration](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/)
