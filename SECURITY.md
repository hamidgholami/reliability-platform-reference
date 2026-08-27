# Security Policy

## Supported versions

Before the first stable release, only the current `main` branch is supported.
This repository is a reference implementation, not a managed service or a
security warranty.

## Reporting a vulnerability

Use GitHub private vulnerability reporting after the repository is published.
Do not open a public issue containing an exploit, secret, private address,
personal data, or other sensitive evidence. Until a private reporting channel
exists, keep the report local and contact the maintainer through a private,
verified channel.

Include the affected revision, impact, minimal reproduction, and suggested
mitigation when possible. The maintainer will acknowledge a valid report and
coordinate disclosure after a fix or documented mitigation is available.

## Repository security rules

- Never commit credentials, private keys, recovery keys, TOTP seeds, unredacted
  logs, Terraform state, kubeconfigs, Vault bootstrap material, or cloud account
  identifiers that should remain private.
- Use synthetic names and addresses in public examples.
- Revoke or rotate a secret immediately if it enters Git history; removing the
  file is not sufficient.
- Keep test fixtures obviously fake and make their purpose explicit.

The initial threat model is in [docs/threat-model.md](docs/threat-model.md).
