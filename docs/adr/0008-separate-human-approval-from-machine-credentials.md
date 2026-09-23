# ADR-0008: Separate human approval from machine credentials

- Status: accepted
- Date: 2026-09-23
- Decider: Hamid Gholami

## Context

The Phase 0 architecture assigned human SSO and MFA to Keycloak but also
described OpenBao or Vault as validating a deployment TOTP. That wording mixes
two different proofs. A personal TOTP presented during a Keycloak authentication
ceremony can contribute to evidence that an identified human is present. A TOTP
code readable by an automated workload proves only that the workload can access
the seed or generation endpoint; it cannot independently prove fresh human
presence or identify an approver.

Phase 2 must establish identity, policy, and short-lived credential boundaries,
but Jenkins and the delivery application that consumes an approval do not begin
until Phase 4. Implementing a deployment TOTP engine now would therefore create
a credential mechanism without a current consumer and encourage a future
pipeline to handle reusable human-factor material.

## Decision

Keycloak owns human authentication. Privileged approvers use individual
identities and must satisfy the accepted password, personal TOTP, and WebAuthn
flow. Keycloak roles and authentication-context claims express who authenticated
and how.

OpenBao owns machine authentication, authorization policy, dynamic secrets, and
short-lived SSH certificates. It does not store, generate, receive, or validate
the personal TOTP used for human approval.

Phase 2 creates the approver roles, proves the required authentication context,
maps human OIDC identity to bounded OpenBao policy, and proves the constrained
SSH-signing boundary. Phase 4 may add a small delivery approval application that
requires fresh Keycloak authentication and binds the approver, build, artifact,
target, expiry, and single-use nonce before requesting an OpenBao-signed machine
credential. Jenkins never receives the human's TOTP or WebAuthn credential.

Do not enable the OpenBao TOTP secrets engine without a concrete legacy target
that accepts only TOTP. Such a future adapter must be optional and must describe
the generated code as a machine compatibility credential, not a human factor.

## Consequences

- Human attribution and MFA stay in the identity system designed to manage
  users and authenticators.
- OpenBao policies and audit records describe machine credential issuance
  without pretending that machine access to a TOTP proves human presence.
- Phase 2 can validate the trust boundaries without implementing Jenkins or an
  approval application early.
- Phase 4 must implement artifact binding, freshness, expiry, replay prevention,
  and independent verification before a production-like deployment path is
  accepted.
- A legacy TOTP-only target would require a separate, narrowly scoped exception
  and credential-leakage tests.

## Alternatives considered

- **Store a shared human TOTP seed in OpenBao:** rejected because an authorized
  workload could synthesize the supposed human factor and attribution would be
  lost.
- **Pass a person's TOTP through Jenkins:** rejected because pipeline inputs,
  logs, process arguments, and resumable state create unnecessary exposure and
  couple human authentication to the automation engine.
- **Enable OpenBao TOTP now for future use:** rejected because no current Phase 2
  consumer requires it.
- **Let a Jenkins input step alone represent approval:** rejected for the future
  production-like path because it does not by itself establish the required MFA
  context or artifact-bound, non-replayable authorization record.

## Validation and reversal

Phase 2 must prove that a user missing any required factor or approver role
cannot obtain privileged OIDC-mapped access, and that machine policy alone
cannot assert human approval. Phase 4 must test freshness, role and issuer
validation, artifact and environment binding, expiry, single use, replay
rejection, and absence of human authenticators from pipeline state.

Reconsider only for a named target that cannot accept workload identity or SSH
certificates. A superseding decision must retain individual human approval and
must not describe a machine-readable TOTP as a human factor.

## References

- [Keycloak authentication flows](https://www.keycloak.org/docs/latest/server_admin/#_authentication-flows)
- [OpenBao JWT/OIDC authentication](https://openbao.org/docs/auth/jwt/)
- [OpenBao signed SSH certificates](https://openbao.org/docs/secrets/ssh/signed-ssh-certificates/)
