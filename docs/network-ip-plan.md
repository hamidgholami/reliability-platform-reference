# Network and IP Plan

Status: draft; validate against the actual workstation and cloud networks before
implementation.

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
API. Under the proposed DNS role split, two BIND 9 instances serve the private
platform namespace and forward other queries upstream. Kubernetes CoreDNS
continues to serve cluster-local discovery and forwards platform-zone queries
to BIND.

Services communicate by DNS name, never by an address copied into application
configuration. Public DNS must not publish RFC 1918 addresses.

## Cloud mapping

Cloud profiles receive non-overlapping CIDRs and provider-native DHCP/routing.
Modules expose a common output contract for subnet, gateway, DNS, and service
addresses while allowing provider-specific topology. Peering or VPN work must
include an overlap check before apply.
