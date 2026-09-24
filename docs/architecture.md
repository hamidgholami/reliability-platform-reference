# Reference Architecture

Status: accepted baseline; revised by ADR-0006 through ADR-0008

## System intent

Reliability Platform Reference is one delivery and operations system with
multiple environment profiles. The first deployment target is a standalone
Incus host on one Debian VM, initially supplied by a minimal isolated AWS
bootstrap root. The maintainer workstation supplies fast checks and optional
reusable local integration; it is not required to host the platform. Later cloud
profiles reuse the interfaces and operational contracts without pretending all
providers are identical.

```text
Developer
   |
   v
Jenkins + approval broker -------> OpenBao -------> short-lived credentials
   |                                  |
   v                                  v
Artifact and image stores       SSH certificates / dynamic secrets
   |
   v
GitOps desired state ----------> Kubernetes workloads
   |                                  |
   +---------- evidence <-------------+
                 |
                 v
       Metrics, logs, traces, SLOs
                 |
                 v
       Backup, restore, and game days
```

## Architectural layers

1. **Workstation and governance** — repository policy, local checks, signed
   human commits, ADRs, and cost/destruction guardrails.
2. **Foundation** — networking, DNS, PKI, Incus hosts, and environment inventory.
3. **Identity and secrets** — Keycloak for human SSO/MFA and approver roles;
   OpenBao for machine identity, dynamic secrets, and SSH certificates.
4. **Delivery** — Jenkins pipelines, an original shared library, artifact stores,
   policy checks, approvals, and GitOps promotion.
5. **Runtime** — Kubernetes built with Kubespray, plus selected infrastructure
   services outside the workload cluster.
6. **Reliability** — telemetry, SLOs, alerting, backup, restore, failure
   injection, and measured recovery evidence.

Implementation follows
[ADR-0006](adr/0006-use-progressive-single-node-delivery.md): complete one
working vertical increment before expanding topology. The initial VM runs only
the services needed by the active increment; the full architecture is not a
promise that every planned service runs concurrently on the minimum host.

## Service placement

The default placement is deliberately split. Jenkins, the approval broker,
Keycloak, OpenBao, PostgreSQL, Pulp, Harbor, observability services, edge
services, and backup infrastructure run on dedicated Incus instances outside
the workload Kubernetes cluster. Sample applications, Traefik Gateway API,
MetalLB, GitOps controllers, cert-manager, agents, and Velero run inside it.

This prevents the workload cluster from becoming the only route to its own
identity, recovery, and deployment control plane. See
[ADR-0002](adr/0002-service-placement.md).

## Bootstrap dependency graph

```text
Human workstation and signed repository
              |
              v
Host OS + network + external DNS delegation
              |
              v
Ansible --> Incus host/cluster
              |
              v
Official Incus OpenTofu provider --> network/storage/DNS-zone resources
              |                         |
              v                         +--> Incus foundational instances
Ansible guest configuration             +--> BIND 9 secondaries + internal CA
              |                         +--> PostgreSQL
              |                         +--> Keycloak
              |                         +--> OpenBao
              v
Kubespray --> Kubernetes --> GitOps --> applications and agents
                                  |
                                  +--> CoreDNS for cluster service discovery
              |
              v
Jenkins delivery, telemetry, backup, restore, and reliability tests
```

Ansible owns host installation, prerequisites, and cluster enrollment. The
official Incus OpenTofu provider owns API-managed Incus resources. Neither tool
silently takes ownership of the other's objects.

The bootstrap, resource, TSIG, and state boundary is defined in
[ADR-0005](adr/0005-separate-incus-bootstrap-and-resource-ownership.md).

The DNS boundary uses Incus network zones as the hidden primary, BIND 9 outside
Kubernetes as the query-serving secondaries, and CoreDNS inside Kubernetes for
cluster service discovery. See
[ADR-0003](adr/0003-separate-platform-and-kubernetes-dns-roles.md).

[ADR-0007](adr/0007-use-openbao-as-the-secrets-runtime.md) selects one secrets
runtime instead of a dual-product matrix.
[ADR-0008](adr/0008-separate-human-approval-from-machine-credentials.md)
separates Keycloak human MFA and approval evidence from OpenBao-issued machine
credentials.

## Failure-domain rules

- An Incus cluster is either one non-HA development member or at least three
  members; a two-member cluster is rejected.
- Control-plane dependencies needed for recovery must not exist only inside the
  failed workload cluster.
- Backups need a second failure domain and restore evidence. A backup tool's
  successful exit code is not recovery proof.
- A cloud provider's managed feature may replace an implementation detail, but
  it must satisfy the same documented identity, evidence, cost, and recovery
  contract.

## Explicit non-claims

Phase 0 deploys nothing. The architecture does not yet prove high availability,
production readiness, secure configuration, RPO/RTO achievement, or portability.
Those claims require later automated tests and published evidence.
