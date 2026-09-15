# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

# This data source proves provider authentication without creating an Incus
# resource. Provider-owned substrate resources are added in the next P1-05
# slice after this trust boundary passes.
data "incus_cluster" "target" {
  remote = var.incus_remote
}

check "standalone_target" {
  assert {
    condition     = !data.incus_cluster.target.is_clustered
    error_message = "Phase 1 supports only a standalone Incus target."
  }
}
