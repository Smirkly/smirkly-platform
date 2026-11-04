import http.client
import json
import os
import re
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from http.cookies import SimpleCookie
from typing import Any, Mapping


AUTH_BASE_URL = os.getenv("AUTH_BASE_URL", "http://127.0.0.1:18080")
MAILPIT_BASE_URL = os.getenv("MAILPIT_BASE_URL", "http://127.0.0.1:8025")
WAIT_TIMEOUT_SECONDS = float(os.getenv("E2E_WAIT_TIMEOUT_SECONDS", "90"))
POLL_INTERVAL_SECONDS = 0.25


@dataclass(frozen=True)
class Response:
    status: int
    headers: Mapping[str, str]
    body: bytes

    def json(self) -> Any:
        return json.loads(self.body.decode("utf-8"))

    def text(self) -> str:
        return self.body.decode("utf-8", errors="replace")


def request(
    base_url: str,
    method: str,
    path: str,
    *,
    body: Mapping[str, Any] | None = None,
    headers: Mapping[str, str] | None = None,
    timeout: float = 5,
) -> Response:
    payload = None
    request_headers = dict(headers or {})
    if body is not None:
        payload = json.dumps(body).encode("utf-8")
        request_headers["Content-Type"] = "application/json"

    http_request = urllib.request.Request(
        urllib.parse.urljoin(base_url.rstrip("/") + "/", path.lstrip("/")),
        data=payload,
        headers=request_headers,
        method=method,
    )

    try:
        with urllib.request.urlopen(http_request, timeout=timeout) as response:
            return Response(response.status, dict(response.headers), response.read())
    except urllib.error.HTTPError as error:
        return Response(error.code, dict(error.headers), error.read())


def assert_status(test: unittest.TestCase, response: Response, expected: int) -> None:
    test.assertEqual(
        response.status,
        expected,
        msg=f"expected HTTP {expected}, got {response.status}: {response.text()}",
    )


def bearer(access_token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {access_token}"}


def refresh_cookie(response: Response) -> str:
    raw_cookie = response.headers.get("Set-Cookie")
    if not raw_cookie:
        raise AssertionError("response does not contain Set-Cookie")

    parsed = SimpleCookie()
    parsed.load(raw_cookie)
    if "refresh_token" not in parsed:
        raise AssertionError("response does not contain refresh_token cookie")
    return parsed["refresh_token"].value


def wait_for_auth() -> None:
    deadline = time.monotonic() + WAIT_TIMEOUT_SECONDS
    last_error: BaseException | None = None

    while time.monotonic() < deadline:
        try:
            response = request(
                AUTH_BASE_URL,
                "GET",
                "/auth/v0/.well-known/jwks.json",
            )
            if response.status == 200:
                return
            last_error = RuntimeError(
                f"JWKS endpoint returned HTTP {response.status}: {response.text()}"
            )
        except (OSError, urllib.error.URLError, http.client.HTTPException) as error:
            last_error = error
        time.sleep(POLL_INTERVAL_SECONDS)

    raise AssertionError(
        f"smirkly-auth did not become ready at {AUTH_BASE_URL}: {last_error}"
    )


def wait_for_mail(*, recipient: str, subject: str) -> str:
    deadline = time.monotonic() + WAIT_TIMEOUT_SECONDS
    seen_subjects: set[str] = set()
    query = urllib.parse.urlencode({"query": f"to:{recipient}"})

    while time.monotonic() < deadline:
        try:
            search = request(
                MAILPIT_BASE_URL,
                "GET",
                f"/api/v1/search?{query}",
            )
            if search.status == 200:
                for message in search.json().get("messages", []):
                    message_subject = message.get("Subject", "")
                    seen_subjects.add(message_subject)
                    if message_subject != subject:
                        continue

                    message_id = urllib.parse.quote(message["ID"], safe="")
                    content = request(
                        MAILPIT_BASE_URL,
                        "GET",
                        f"/view/{message_id}.txt",
                    )
                    if content.status == 200:
                        return content.text()
        except (OSError, ValueError, urllib.error.URLError, http.client.HTTPException):
            pass

        time.sleep(POLL_INTERVAL_SECONDS)

    raise AssertionError(
        f"Mailpit did not receive {subject!r} for {recipient}; "
        f"seen subjects: {sorted(seen_subjects)}"
    )


def extract(pattern: str, text: str, value_name: str) -> str:
    match = re.search(pattern, text)
    if not match:
        raise AssertionError(f"could not extract {value_name} from email: {text}")
    return match.group(1)


class AuthLifecycleE2E(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        wait_for_auth()

    def test_complete_auth_lifecycle_through_mailpit(self) -> None:
        suffix = uuid.uuid4().hex[:12]
        username = f"e2e_{suffix}"
        email = f"e2e-{suffix}@example.com"
        old_password = "StrongPass123!"
        new_password = "NewStrongPass456!"

        sign_up = request(
            AUTH_BASE_URL,
            "POST",
            "/auth/v0/sign-up",
            body={
                "username": username,
                "email": email,
                "password": old_password,
            },
        )
        assert_status(self, sign_up, 201)
        self.assertEqual(sign_up.json()["user"]["email"], email)

        verification_mail = wait_for_mail(
            recipient=email,
            subject="Smirkly verification code",
        )
        verification_code = extract(
            r"Your verification code:\s*([0-9]{6})",
            verification_mail,
            "verification code",
        )

        verify = request(
            AUTH_BASE_URL,
            "POST",
            "/auth/v0/verify-email",
            body={"email": email, "code": verification_code},
        )
        assert_status(self, verify, 204)

        sign_in = request(
            AUTH_BASE_URL,
            "POST",
            "/auth/v0/sign-in",
            body={"username": username, "password": old_password},
        )
        assert_status(self, sign_in, 200)
        sign_in_body = sign_in.json()
        first_access_token = sign_in_body["tokens"]["access_token"]
        first_session_id = sign_in_body["session_id"]
        first_refresh_token = refresh_cookie(sign_in)

        me = request(
            AUTH_BASE_URL,
            "GET",
            "/auth/v0/me",
            headers=bearer(first_access_token),
        )
        assert_status(self, me, 200)
        self.assertEqual(me.json()["user"]["username"], username)

        sessions = request(
            AUTH_BASE_URL,
            "GET",
            "/auth/v0/sessions",
            headers=bearer(first_access_token),
        )
        assert_status(self, sessions, 200)
        self.assertTrue(
            any(
                session["id"] == first_session_id and session["current"]
                for session in sessions.json()["sessions"]
            )
        )

        refreshed = request(
            AUTH_BASE_URL,
            "POST",
            "/auth/v0/refresh",
            headers={"Cookie": f"refresh_token={first_refresh_token}"},
        )
        assert_status(self, refreshed, 200)
        refreshed_body = refreshed.json()
        second_access_token = refreshed_body["tokens"]["access_token"]
        second_session_id = refreshed_body["session_id"]
        second_refresh_token = refresh_cookie(refreshed)
        self.assertNotEqual(first_session_id, second_session_id)
        self.assertNotEqual(first_refresh_token, second_refresh_token)

        old_access = request(
            AUTH_BASE_URL,
            "GET",
            "/auth/v0/me",
            headers=bearer(first_access_token),
        )
        assert_status(self, old_access, 401)

        current_access = request(
            AUTH_BASE_URL,
            "GET",
            "/auth/v0/me",
            headers=bearer(second_access_token),
        )
        assert_status(self, current_access, 200)
        self.assertEqual(current_access.json()["session_id"], second_session_id)

        reset_request = request(
            AUTH_BASE_URL,
            "POST",
            "/auth/v0/password-reset/request",
            body={"email": email},
        )
        assert_status(self, reset_request, 204)

        reset_mail = wait_for_mail(
            recipient=email,
            subject="Smirkly password reset",
        )
        reset_token = extract(
            r"Your password reset token:\s*([^\s]+)",
            reset_mail,
            "password reset token",
        )

        reset_confirm = request(
            AUTH_BASE_URL,
            "POST",
            "/auth/v0/password-reset/confirm",
            body={
                "email": email,
                "token": reset_token,
                "new_password": new_password,
            },
        )
        assert_status(self, reset_confirm, 204)

        access_after_reset = request(
            AUTH_BASE_URL,
            "GET",
            "/auth/v0/me",
            headers=bearer(second_access_token),
        )
        assert_status(self, access_after_reset, 401)

        old_password_sign_in = request(
            AUTH_BASE_URL,
            "POST",
            "/auth/v0/sign-in",
            body={"username": username, "password": old_password},
        )
        assert_status(self, old_password_sign_in, 401)

        new_password_sign_in = request(
            AUTH_BASE_URL,
            "POST",
            "/auth/v0/sign-in",
            body={"username": username, "password": new_password},
        )
        assert_status(self, new_password_sign_in, 200)
        final_body = new_password_sign_in.json()
        final_access_token = final_body["tokens"]["access_token"]
        final_refresh_token = refresh_cookie(new_password_sign_in)

        logout = request(
            AUTH_BASE_URL,
            "POST",
            "/auth/v0/logout",
            headers=bearer(final_access_token),
        )
        assert_status(self, logout, 204)

        access_after_logout = request(
            AUTH_BASE_URL,
            "GET",
            "/auth/v0/me",
            headers=bearer(final_access_token),
        )
        assert_status(self, access_after_logout, 401)

        refresh_after_logout = request(
            AUTH_BASE_URL,
            "POST",
            "/auth/v0/refresh",
            headers={"Cookie": f"refresh_token={final_refresh_token}"},
        )
        assert_status(self, refresh_after_logout, 401)


if __name__ == "__main__":
    unittest.main()
