# ADR-0003: Separate platform and Kubernetes DNS roles

- Status: accepted
- Date: 2026-08-28
- Decider: Hamid Gholami

## Context

The platform needs private authoritative records for services on Incus as well
as Kubernetes-native service discovery. Incus managed networks already provide
DHCP and local DNS, and Incus network zones automatically generate forward and
reverse records for instances, gateways, and downstream ports. They also support
custom records through the Incus API.

The Incus network-zone server is intended as a zone-transfer source. It supports
AXFR but does not answer ordinary DNS queries, so clients still need a
query-serving authoritative DNS server. Using CoreDNS for that external role
would also blur the platform and Kubernetes DNS boundaries.

The registered public domain is already delegated to Netcup. Public DNS hosting
and private platform DNS are separate concerns: the public zone must not reveal
private service addresses.

## Decision

Use Netcup for public authoritative DNS. Configure Incus forward and reverse
network zones and attach them to the managed Incus network. The Incus built-in
DNS server is the hidden primary: it generates records from Incus state and
exposes zones only to approved transfer peers.

Run two BIND 9 services on foundational Incus instances as authoritative
secondaries. They receive zones from Incus through authenticated AXFR and
NOTIFY, answer ordinary client queries, and do not provide general recursive
resolution. Keep CoreDNS inside Kubernetes for `cluster.local` discovery and
forward only the private platform namespace to the BIND pair.

Ansible manages the Incus zone declarations, manual records, transfer peers,
TSIG material references, and BIND secondary configuration. Incus bridge DNS
forwards the private namespace to BIND and resolves other names through its
normal upstream path. Trusted workstations and VPN resolvers conditionally
forward only the private namespace to BIND. None of these DNS endpoints is
exposed publicly.

## Rationale

Incus remains authoritative for its own infrastructure state, which avoids
declaring every instance address twice. BIND adds the query-serving and
secondary-authority layer that Incus network zones deliberately do not provide.
The design demonstrates automatic IPAM-derived records, hidden-primary
topology, authenticated transfer, notifications, split DNS, and secondary
recovery. CoreDNS remains the natural Kubernetes component because its
Kubernetes plugin discovers Services and Pods directly.

The split adds one product but gives each server a narrow role. It also keeps
private name resolution available while the workload cluster is unavailable.

## Consequences

- Incus automatically creates and removes records as instance/network state
  changes. Manually editing the transferred BIND zone is prohibited.
- Manual service records and aliases remain declarative in Git and are applied
  through the Incus network-zone API.
- BIND secondary configuration, transfers, monitoring, expiry behavior, and
  recovery need their own automation and tests.
- Existing BIND secondaries can continue answering a transferred zone during a
  temporary Incus control-plane outage, subject to the zone's SOA expiry.
- Kubernetes DNS depends on the BIND pair only for platform names, not for
  cluster-local service discovery.
- Clients outside Kubernetes use the platform resolvers and receive private
  split-horizon answers.
- Netcup remains sufficient for public DNS; Cloudflare is optional rather than
  architectural.

## Alternatives considered

- Use CoreDNS everywhere: simpler and lightweight, but provides less depth for
  authoritative infrastructure DNS and combines distinct operational roles.
- Use only the managed-bridge DNS server: sufficient for a small single-network
  lab, but it does not provide the query-serving network-zone architecture and
  independent secondaries required by the reference platform.
- Make BIND the primary and duplicate Incus records in BIND zone data: rejected
  because it creates two competing sources for instance identity and addresses.
- Use BIND inside Kubernetes too: rejected because Kubernetes-native service
  discovery is already handled well by CoreDNS.
- Delegate public DNS to Cloudflare: unnecessary for the current requirements;
  reconsider only if its automation, proxy, or security services become a
  justified dependency.

## Validation and reversal

Verify that creating, renaming, and deleting an Incus instance updates forward
and reverse answers through both BIND secondaries. Test custom records,
authenticated transfer and notification, either BIND instance being
unavailable, a temporary hidden-primary outage, and resolution through Incus
DNS, trusted workstation split DNS, and Kubernetes CoreDNS. Reverse the choice
with a superseding ADR if its operational cost is not justified by the
demonstrated capability.

## References

- [BIND 9 Administrator Reference Manual](https://bind9.readthedocs.io/en/latest/)
- [CoreDNS manual](https://coredns.io/manual/toc/)
- [Incus network zones](https://linuxcontainers.org/incus/docs/main/howto/network_zones/)
- [Incus managed bridge](https://linuxcontainers.org/incus/docs/main/reference/network_bridge/)
- [Kubernetes DNS customization](https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/)
- [Netcup domain documentation](https://www.netcup.com/en/helpcenter/documentation/domain)
- [cert-manager Cloudflare DNS-01 integration](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/)
