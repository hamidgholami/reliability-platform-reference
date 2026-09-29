# ADR-0009: Pin disposable machine certificates during guarded recovery

- Status: proposed
- Date: 2026-09-29
- Deciders: project maintainer

## Context

P2-03 needs one machine identity before Keycloak supplies ordinary operator
authentication. The initial OpenBao root token is retired. The existing
certificate and Shamir-share ceremony can generate a temporary root token and
revoke it after use.

A token allowed to edit the machine ACL policy and certificate role could
replace either with broader permissions, then authenticate with a certificate
it controls. Limiting that token to two object names does not limit the rights
those objects can grant.

## Decision

Generate an Ed25519 X.509 client key inside the disposable `smoke-01` instance.
During guarded root recovery, write the fixed machine policy and exact-pin the
public leaf certificate to a dedicated `cert` auth role. Require a five-minute
explicit token maximum and no default policy. Revoke the temporary root and
recovery login before proving the machine login and capabilities.

Do not issue a separate configuration token for editing the machine role or
policy. Repeating this operation requires the same guarded ceremony. The
machine key stays in its instance, and the human recovery credential is never
used for routine machine login.

## Consequences

- The operator must perform a recovery ceremony for initial setup and rotation
  until a bounded human configuration path exists.
- A recreated `smoke-01` requires a new public certificate pin.
- Policy or role changes require a new ceremony; the machine token cannot edit
  either object.
- Failed configuration may leave a partial policy or role. The helper attempts
  root-token revocation in cleanup; an operator inspects token and audit state
  before retrying if revocation cannot be confirmed.

## Alternatives considered

- **Short-lived token allowed to edit the named policy and role:** rejected
  because it could widen either object and authenticate through the widened
  role.
- **Standing operator certificate:** deferred until the planned human OIDC
  authentication path exists.

## Validation and reversal

Prove the machine can log in with only its dedicated policy and cannot access
operator KV or system mounts. Confirm the generated root is revoked before
acceptance. Revisit this ceremony when P2-04 supplies human identity and a
configuration path that cannot edit its own authority.

## References

- [OpenBao certificate auth API](https://openbao.org/docs/2.6.x/api/auth/cert/)
- [OpenBao ACL policies](https://openbao.org/docs/2.6.x/api/system/policies/)
