# ADR-0001: Build one integrated reference platform

- Status: accepted
- Date: 2026-08-27
- Decider: Hamid Gholami

## Context

The existing portfolio consists of many small laboratories with duplicated
Vagrant, Ansible, Jenkins, Kubernetes, and Terraform concerns. Individual labs
show learning but do not clearly demonstrate how an SRE designs, secures,
operates, measures, and recovers a real delivery platform.

## Decision

Build `reliability-platform-reference` as the flagship repository. It will expose
one coherent architecture and common operating contracts across a local Incus
reference and selected cloud profiles. Previous labs remain research inputs and
are not merged wholesale.

Implementation follows dependency-ordered phases. A product is included only
when it has a clear platform role, owner, validation path, and maintained
no-cost alternative where needed.

## Consequences

The repository provides a stronger portfolio narrative and encourages end-to-end
tests. It also requires more disciplined boundaries and documentation than a
collection of demos. Breadth is intentionally limited; Puppet, Nomad, Ceph, and
other products do not enter the critical path without a demonstrated need.

## Alternatives considered

- Continue improving every small lab: rejected because duplication and missing
  integration remain visible.
- Create a monorepo containing all old code: rejected because obsolete,
  duplicated, private, or incompatible material would obscure authorship and
  architecture.
- Create one repository per product: retained only for genuinely separate
  learning tracks such as K3s, not the flagship platform.

## Validation and reversal

Validate with a traceable commit-to-deployment-to-observation-to-recovery demo.
Split a component only if independent lifecycle, audience, or security ownership
outweighs the value of integrated evidence.
