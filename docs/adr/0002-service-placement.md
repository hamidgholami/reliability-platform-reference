# ADR-0002: Keep recovery control services outside the workload cluster

- Status: accepted
- Date: 2026-08-27
- Decider: Hamid Gholami

## Context

Putting every platform service inside one Kubernetes cluster is compact, but a
cluster failure can remove the identity, delivery, observability, and recovery
systems needed to diagnose or rebuild that cluster.

## Decision

Run Jenkins, the approval broker, Keycloak, Vault/OpenBao, PostgreSQL, Pulp,
Harbor, core observability services, edge services, and backup infrastructure on
dedicated Incus instances outside the workload cluster.

Run sample workloads, Traefik Gateway API, MetalLB, GitOps controllers,
cert-manager, cluster agents, and Velero inside Kubernetes. Define explicit
backup, authentication, and network contracts across the boundary.

## Consequences

Recovery and delivery control remain available during many workload-cluster
failures, and service ownership is easier to demonstrate. The design requires
more instances, external-service lifecycle automation, and careful protection of
the Incus foundation. A later HA profile needs independent failure domains rather
than merely more instances on one host.

## Alternatives considered

- Put everything in Kubernetes: rejected for the reference profile because of
  circular recovery dependencies.
- Put every service outside Kubernetes: rejected because workload-native GitOps,
  certificates, networking, and Velero belong with the cluster they control.
- Use managed SaaS for all control services: unsuitable for the local-first,
  reproducible, no-additional-subscription goal.

## Validation and reversal

Validate by making the workload cluster unavailable and demonstrating access to
identity, secrets, delivery records, telemetry, and restore control. Revisit
individual placements when measured operational cost exceeds the recovery
benefit and an alternative preserves the failure boundary.
