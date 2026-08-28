# Network and IP Plan

Status: accepted Phase 0 baseline; cloud ranges still require per-environment
validation before implementation.

## Local reference allocation

| Range | Intended use |
| --- | --- |
| `10.20.0.0/24` | Incus reference network |
| `10.20.0.1` | Incus-managed gateway and DNS forwarder |
| `10.20.0.10-29` | Foundational services with stable leases/addresses |
| `10.20.0.30-79` | Kubernetes nodes |
| `10.20.0.80-119` | Load-balancer addresses |
| `10.20.0.120-219` | General dynamic instances |
| `10.20.0.220-254` | Reserved for experiments and migration |

The actual values are inputs, not constants embedded in roles or modules.

## DHCP and name resolution

Incus provides its own managed bridge, DHCP, DNS, and NAT for local instances;
no physical router, switch, or firewall appliance is required. Stable services
use explicit instance addresses or DHCP reservations managed through the Incus
API.

Incus forward and reverse network zones form the hidden DNS primary and derive
records automatically from instance and network state. Two BIND 9 instances are
authoritative secondaries: they receive the zones from Incus through
authenticated transfer and answer client queries. Incus managed-bridge DNS
forwards the private platform namespace to BIND and resolves other names through
its normal upstream path. Kubernetes CoreDNS continues to serve cluster-local
discovery and forwards only platform-zone queries to the BIND pair.

Trusted workstations use split DNS for the platform namespace. On macOS this can
be represented by a resolver entry for `dev.apadanalab.de`; Linux clients use an
equivalent route-only domain or conditional-forwarding configuration. VPN and
future site networks must provide the same conditional DNS route.

DNS resolution does not create network reachability. A client must also have a
route to `10.20.0.0/24`, directly through the Incus host or through a trusted
VPN. This is especially important when the Incus host runs behind a Linux VM on
a macOS workstation.

Services communicate by DNS name, never by an address copied into application
configuration. Public DNS must not publish RFC 1918 addresses.

## Cloud mapping

Cloud profiles receive non-overlapping CIDRs and provider-native DHCP/routing.
Modules expose a common output contract for subnet, gateway, DNS, and service
addresses while allowing provider-specific topology. Peering or VPN work must
include an overlap check before apply.
