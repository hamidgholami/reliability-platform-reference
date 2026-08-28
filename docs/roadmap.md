# Roadmap

The roadmap builds demonstrable capability in dependency order. Each phase needs
an implementation plan, acceptance evidence, and rollback or teardown path.

| Phase | Outcome |
| --- | --- |
| 0 | Architecture, governance, repository checks, and approved boundaries |
| 1 | Reproducible Incus and network foundation through an original Ansible role |
| 2 | Identity, PKI, Vault/OpenBao, dynamic secrets, SSH certificates, and approvals |
| 3 | Kubespray Kubernetes foundation and GitOps bootstrap |
| 4 | Jenkins platform library and end-to-end delivery path using a coherent sample application |
| 5 | Artifact and supply-chain controls with Pulp and Harbor |
| 6 | Metrics, logs, traces, SLOs, and actionable alerting |
| 7 | Borg infrastructure backup, Velero cluster recovery, and restore evidence |
| 8 | AWS profiles and selected Azure integrations with cost controls |
| 9 | Failure injection, game days, portfolio evidence, and stable release |

After the stable release, legacy repositories can be scanned and individually
retained, archived, or marked as superseded. That cleanup is not on the critical
path for this platform.

K3s remains a separate lightweight learning track. Puppet is not a priority
unless a real legacy-management scenario justifies its maintenance cost. Nomad,
Ceph, and similar systems are considered only when they close a demonstrated
capability gap rather than expand the product list.

The active execution plan is
[Phase 0 architecture and governance](plans/phase-0-architecture-and-governance.md).

Phase 4 will introduce a small, coherent Java Spring Boot application as the
system under delivery. It will demonstrate build, unit and integration tests,
artifact publication, promotion, deployment, observability, rollback, and
eventually browser-based QA with Selenium or an equivalent maintained tool. No
application implementation belongs in the current phase.
