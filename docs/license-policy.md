# License and Third-Party Policy

Repository-authored source, configuration, and documentation are distributed
under Apache License 2.0. The root `LICENSE` and `NOTICE` provide the governing
text and initial attribution.

## File policy

Source-like files that support comments use:

```text
SPDX-FileCopyrightText: 2026 Hamid Gholami
SPDX-License-Identifier: Apache-2.0
```

Markdown prose is covered by the repository license and root notice without a
repeated visible header. Vendored or generated material must preserve its own
notices and be clearly separated from original work.

## Third-party products

Mentioning or automating a product does not relicense that product. Before a
foundational dependency is introduced, record:

- exact component and version;
- purpose and operational ownership;
- upstream license and source location;
- whether the required features are no-cost;
- a maintained open-source alternative and migration consequence;
- redistribution obligations for any bundled artifact.

The architecture may demonstrate Terraform-compatible workflows, Vault, or
other products with source-available or commercial editions, but must keep an
OpenTofu, OpenBao, or equivalent no-cost path where practical and document any
feature gap. This policy is engineering guidance, not legal advice.

Do not copy code from private employer repositories. Reimplement learned
patterns independently and cite only public upstream material.
