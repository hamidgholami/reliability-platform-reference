# Naming and Repository Conventions

## Names

- Use lowercase kebab-case for repositories, directories, DNS labels, and human
  resource names: `reliability-platform-reference`, `approval-broker`.
- Use snake_case where required by Ansible and Python variables: `incus_host`.
- Use lowerCamelCase or the ecosystem convention only when an API requires it.
- Names describe capability, not an internal company or former project.
- Environment comes after the service in DNS:
  `vault.dev.apadanalab.de`.

## Repository layout

Create a top-level product directory only when its implementation phase begins
and it contains an owned artifact. Do not create empty placeholders. Each
implementation area eventually includes its purpose, inputs, validation,
security considerations, and teardown or rollback path.

Public examples use reserved documentation addresses and synthetic identities.
Employer names, private repository paths, ticket IDs, internal hostnames, and
copied code are prohibited.

## Interfaces

- `make` is the human-facing command interface.
- Environment inputs are explicit and validated; hidden workstation state is
  not an input contract.
- Generated files identify their source and are not edited manually.
- Architecture decisions use sequential ADRs in `docs/adr/`.
- Task-level execution plans live in `docs/plans/` and include validation and
  rollback.
