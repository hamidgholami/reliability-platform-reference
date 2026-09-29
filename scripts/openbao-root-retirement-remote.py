#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Hamid Gholami
# SPDX-License-Identifier: Apache-2.0

"""Run authenticated root recovery for retirement or machine-auth setup."""

from __future__ import annotations

import http.client
import json
import ssl
import sys
from pathlib import Path
from typing import Any


API_HOST = "10.20.0.20"
API_PORT = 8200
CA_FILE = "/opt/openbao/tls/ca.crt"
RECOVERY_ROLE = "rpr-root-generation"
RECOVERY_POLICY = "rpr-root-generation"
ADMIN_POLICY = "rpr-bootstrap-admin"
MACHINE_ROLE = "rpr-p203-machine"
MACHINE_POLICY_DOCUMENT = '''path "database/creds/rpr-p203-read" {
  capabilities = ["read"]
}
path "ssh-client-signer/sign/rpr-p203-probe" {
  capabilities = ["update"]
}
path "sys/capabilities-self" {
  capabilities = ["update"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}'''


class CeremonyError(RuntimeError):
    """A redaction-safe ceremony failure."""


def request(
    context: ssl.SSLContext,
    method: str,
    path: str,
    *,
    token: str | None = None,
    body: dict[str, Any] | None = None,
    expected: tuple[int, ...] = (200,),
) -> tuple[int, dict[str, Any]]:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["X-Vault-Token"] = token
    payload = None if body is None else json.dumps(body, separators=(",", ":"))
    connection = http.client.HTTPSConnection(
        API_HOST,
        API_PORT,
        context=context,
        timeout=10,
    )
    try:
        connection.request(method, path, body=payload, headers=headers)
        response = connection.getresponse()
        raw = response.read()
    except (OSError, ssl.SSLError, http.client.HTTPException) as exc:
        raise CeremonyError("OpenBao API transport failed") from exc
    finally:
        connection.close()

    if response.status not in expected:
        raise CeremonyError(
            f"OpenBao API returned unexpected status {response.status} for {path}"
        )
    if not raw:
        return response.status, {}
    try:
        decoded = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise CeremonyError("OpenBao API returned invalid JSON") from exc
    if not isinstance(decoded, dict):
        raise CeremonyError("OpenBao API returned an invalid object")
    return response.status, decoded


def require_text(value: Any, label: str) -> str:
    if not isinstance(value, str) or len(value) < 16:
        raise CeremonyError(f"OpenBao returned an invalid {label}")
    return value


def main() -> int:
    machine_auth = len(sys.argv) == 5 and sys.argv[3] == "--machine-auth"
    if not (len(sys.argv) == 4 or machine_auth):
        raise CeremonyError(
            "usage: remote-helper CLIENT_CERT CLIENT_KEY INITIAL_TOKEN|--machine-auth MACHINE_CERT"
        )

    client_certificate = Path(sys.argv[1])
    client_key = Path(sys.argv[2])
    input_file = Path(sys.argv[4] if machine_auth else sys.argv[3])
    protected_files = [client_certificate, client_key, input_file]
    for protected_file in protected_files:
        if not protected_file.is_file() or protected_file.stat().st_mode & 0o077:
            raise CeremonyError("a protected ceremony input is missing or unsafe")

    unseal_share = require_text(sys.stdin.readline().strip(), "Shamir share")
    initial_token = (
        "" if machine_auth else require_text(input_file.read_text().strip(), "initial token")
    )
    machine_certificate = input_file.read_text().strip() if machine_auth else ""
    if machine_auth and "-----BEGIN CERTIFICATE-----" not in machine_certificate:
        raise CeremonyError("the machine certificate is invalid")

    context = ssl.create_default_context(cafile=CA_FILE)
    context.load_cert_chain(str(client_certificate), str(client_key))

    recovery_token: str | None = None
    generated_root_token: str | None = None
    admin_token: str | None = None
    generation_started = False
    root_revoked = False
    initial_revoked = False
    recovery_revoked = False

    try:
        if not machine_auth:
            _, initial_lookup = request(
                context,
                "GET",
                "/v1/auth/token/lookup-self",
                token=initial_token,
            )
            initial_data = initial_lookup.get("data", {})
            if initial_data.get("policies") != ["root"] or initial_data.get("ttl") != 0:
                raise CeremonyError(
                    "the initial credential is not a non-expiring root token"
                )

        _, login = request(
            context,
            "POST",
            "/v1/auth/cert/login",
            body={"name": RECOVERY_ROLE},
        )
        login_auth = login.get("auth", {})
        recovery_token = require_text(login_auth.get("client_token"), "recovery token")
        if login_auth.get("policies") != [RECOVERY_POLICY]:
            raise CeremonyError("certificate login returned unexpected policies")
        if not 0 < int(login_auth.get("lease_duration", 0)) <= 300:
            raise CeremonyError("certificate login returned an unsafe token TTL")

        _, generation_status = request(
            context,
            "GET",
            "/v1/sys/generate-root-token/attempt",
            token=recovery_token,
        )
        if generation_status.get("data", {}).get("started"):
            raise CeremonyError("another root-token generation attempt is active")

        _, generation_init = request(
            context,
            "POST",
            "/v1/sys/generate-root-token/attempt",
            token=recovery_token,
            body={},
        )
        generation_started = True
        init_data = generation_init.get("data", {})
        nonce = require_text(init_data.get("nonce"), "root-generation nonce")
        otp = require_text(init_data.get("otp"), "root-generation OTP")
        if init_data.get("required") != 1 or init_data.get("complete"):
            raise CeremonyError("root generation does not match the reviewed 1-of-1 seal")

        _, generation_update = request(
            context,
            "POST",
            "/v1/sys/generate-root-token/update",
            token=recovery_token,
            body={"key": unseal_share, "nonce": nonce},
        )
        update_data = generation_update.get("data", {})
        if not update_data.get("complete") or update_data.get("progress") != 1:
            raise CeremonyError("root generation did not reach the required threshold")
        encoded_token = require_text(
            update_data.get("encoded_token"), "encoded root token"
        )
        generation_started = False

        _, decoded = request(
            context,
            "POST",
            "/v1/sys/decode-token",
            body={"encoded_token": encoded_token, "otp": otp},
        )
        generated_root_token = require_text(
            decoded.get("data", {}).get("token"), "generated root token"
        )
        unseal_share = ""
        otp = ""
        encoded_token = ""

        _, root_lookup = request(
            context,
            "GET",
            "/v1/auth/token/lookup-self",
            token=generated_root_token,
        )
        root_data = root_lookup.get("data", {})
        if root_data.get("policies") != ["root"] or root_data.get("ttl") != 0:
            raise CeremonyError("recovery did not create a non-expiring root token")

        if machine_auth:
            request(
                context,
                "POST",
                f"/v1/sys/policies/acl/{MACHINE_ROLE}",
                token=generated_root_token,
                body={"policy": MACHINE_POLICY_DOCUMENT},
                expected=(204,),
            )
            request(
                context,
                "POST",
                f"/v1/auth/cert/certs/{MACHINE_ROLE}",
                token=generated_root_token,
                body={
                    "certificate": machine_certificate,
                    "display_name": MACHINE_ROLE,
                    "allowed_common_names": ["RPR P2-03 Machine Probe"],
                    "allowed_organizational_units": ["Platform Test"],
                    "token_policies": [MACHINE_ROLE],
                    "token_ttl": "5m",
                    "token_max_ttl": "5m",
                    "token_explicit_max_ttl": "5m",
                    "token_no_default_policy": True,
                    "token_type": "service",
                },
                expected=(200, 204),
            )
            _, role_response = request(
                context,
                "GET",
                f"/v1/auth/cert/certs/{MACHINE_ROLE}",
                token=generated_root_token,
            )
            role = role_response.get("data", {})
            if (
                role.get("certificate", "").strip() != machine_certificate
                or role.get("display_name") != MACHINE_ROLE
                or role.get("token_policies") != [MACHINE_ROLE]
                or role.get("token_ttl") != 300
                or role.get("token_max_ttl") != 300
                or role.get("token_explicit_max_ttl") != 300
                or not role.get("token_no_default_policy")
                or role.get("token_type") != "service"
                or role.get("allowed_common_names") != ["RPR P2-03 Machine Probe"]
                or role.get("allowed_organizational_units") != ["Platform Test"]
            ):
                raise CeremonyError("machine certificate role has an unsafe boundary")
        else:
            _, admin_response = request(
                context,
                "POST",
                "/v1/auth/token/create-orphan",
                token=generated_root_token,
                body={
                    "policies": [ADMIN_POLICY],
                    "no_default_policy": True,
                    "renewable": False,
                    "ttl": "5m",
                    "explicit_max_ttl": "5m",
                    "display_name": "rpr-recovery-admin-acceptance",
                },
            )
            admin_auth = admin_response.get("auth", {})
            admin_token = require_text(admin_auth.get("client_token"), "recovery admin token")
            if admin_auth.get("policies") != [ADMIN_POLICY]:
                raise CeremonyError("recovery admin token has unexpected policies")
            if not 0 < int(admin_auth.get("lease_duration", 0)) <= 300:
                raise CeremonyError("recovery admin token has an unsafe TTL")
            request(context, "GET", "/v1/sys/mounts", token=admin_token)
            request(
                context,
                "POST",
                "/v1/auth/token/revoke-self",
                token=admin_token,
                body={},
                expected=(204,),
            )
            admin_token = None

        request(
            context,
            "POST",
            "/v1/auth/token/revoke-self",
            token=generated_root_token,
            body={},
            expected=(204,),
        )
        root_revoked = True
        request(
            context,
            "GET",
            "/v1/auth/token/lookup-self",
            token=generated_root_token,
            expected=(403,),
        )
        generated_root_token = None

        request(
            context,
            "POST",
            "/v1/auth/token/revoke-self",
            token=recovery_token,
            body={},
            expected=(204,),
        )
        recovery_revoked = True
        request(
            context,
            "GET",
            "/v1/auth/token/lookup-self",
            token=recovery_token,
            expected=(403,),
        )
        recovery_token = None

        if machine_auth:
            print('{"machine_auth_configured":true,"temporary_root_revoked":true}')
            return 0

        request(
            context,
            "POST",
            "/v1/auth/token/revoke-self",
            token=initial_token,
            body={},
            expected=(204,),
        )
        initial_revoked = True
        request(
            context,
            "GET",
            "/v1/auth/token/lookup-self",
            token=initial_token,
            expected=(403,),
        )
        initial_token = ""

        print(
            json.dumps(
                {
                    "authenticated_recovery": True,
                    "temporary_root_generated": True,
                    "bounded_admin_proven": True,
                    "temporary_root_revoked": root_revoked,
                    "initial_root_revoked": initial_revoked,
                    "recovery_session_revoked": recovery_revoked,
                },
                separators=(",", ":"),
            )
        )
        return 0
    finally:
        unseal_share = ""
        initial_token = ""
        if admin_token:
            try:
                request(
                    context,
                    "POST",
                    "/v1/auth/token/revoke-self",
                    token=admin_token,
                    body={},
                    expected=(204,),
                )
            except CeremonyError:
                pass
        if generated_root_token:
            try:
                request(
                    context,
                    "POST",
                    "/v1/auth/token/revoke-self",
                    token=generated_root_token,
                    body={},
                    expected=(204,),
                )
            except CeremonyError:
                pass
        if generation_started and recovery_token:
            try:
                request(
                    context,
                    "DELETE",
                    "/v1/sys/generate-root-token/attempt",
                    token=recovery_token,
                    expected=(204,),
                )
            except CeremonyError:
                pass
        if recovery_token:
            try:
                request(
                    context,
                    "POST",
                    "/v1/auth/token/revoke-self",
                    token=recovery_token,
                    body={},
                    expected=(204,),
                )
            except CeremonyError:
                pass


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CeremonyError as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(1) from None
