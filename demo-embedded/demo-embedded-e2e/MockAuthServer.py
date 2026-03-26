#!/usr/bin/env python3

import argparse
import base64
import html
import json
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlencode, urlparse


def b64url_json(data):
    raw = json.dumps(data, separators=(",", ":")).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("utf-8").rstrip("=")


def decode_b64url_json(value):
    if not value:
        return None
    padding = "=" * (-len(value) % 4)
    decoded = base64.urlsafe_b64decode(value + padding)
    return json.loads(decoded.decode("utf-8"))


def make_jwt(payload):
    header = {"alg": "none", "typ": "JWT"}
    return f"{b64url_json(header)}.{b64url_json(payload)}.signature"


def normalize_path(path):
    if not path.startswith("/"):
        return f"/{path}"
    return path


def user_name_from_email(email):
    local = email.split("@", 1)[0].replace("-", " ").replace(".", " ")
    return " ".join(part.capitalize() for part in local.split()) or "Demo User"


def tenant_id_for_email(email):
    local = email.split("@", 1)[0].replace(".", "-").replace("_", "-")
    return f"tenant-{local}"


def tenant_response(email):
    tenant_id = tenant_id_for_email(email)
    now = "2026-03-26T00:00:00.000Z"
    return {
        "id": tenant_id,
        "name": f"{user_name_from_email(email)} Tenant",
        "tenantId": tenant_id,
        "createdAt": now,
        "updatedAt": now,
        "isReseller": False,
        "metadata": "{}",
        "vendorId": "vendor-demo",
    }


def user_response(email):
    tenant = tenant_response(email)
    return {
        "id": f"user-{email.split('@', 1)[0]}",
        "email": email,
        "mfaEnrolled": False,
        "name": user_name_from_email(email),
        "profilePictureUrl": "https://example.com/avatar.png",
        "phoneNumber": None,
        "profileImage": None,
        "roles": [],
        "permissions": [],
        "tenantId": tenant["id"],
        "tenantIds": [tenant["id"]],
        "tenants": [tenant],
        "activeTenant": tenant,
        "activatedForTenant": True,
        "metadata": "{}",
        "verified": True,
        "superUser": False,
    }


def access_token_for_email(email):
    now = int(time.time())
    payload = {
        "sub": f"user-{email.split('@', 1)[0]}",
        "email": email,
        "name": user_name_from_email(email),
        "tenantId": tenant_id_for_email(email),
        "tenantIds": [tenant_id_for_email(email)],
        "profilePictureUrl": "https://example.com/avatar.png",
        "exp": now + 3600,
        "iat": now,
    }
    return make_jwt(payload)


def auth_response_for_email(email, refresh_token=None):
    return {
        "token_type": "Bearer",
        "refresh_token": refresh_token or f"refresh-{uuid.uuid4()}",
        "access_token": access_token_for_email(email),
        "id_token": access_token_for_email(email),
    }


class MockState:
    def __init__(self):
        self.lock = threading.Lock()
        self.reset()

    def reset(self):
        with self.lock:
            self.queues = {}
            self.auth_codes = {}
            self.refresh_tokens = {
                "signup-refresh-token": "signup@frontegg.com",
            }

    def enqueue(self, method, path, responses):
        key = (method.upper(), normalize_path(path))
        with self.lock:
            self.queues.setdefault(key, []).extend(responses)

    def dequeue(self, method, path):
        key = (method.upper(), normalize_path(path))
        with self.lock:
            queue = self.queues.get(key)
            if not queue:
                return None
            response = queue.pop(0)
            if not queue:
                self.queues.pop(key, None)
            return response

    def issue_code(self, email, redirect_uri, state):
        code = f"code-{uuid.uuid4()}"
        with self.lock:
            self.auth_codes[code] = {
                "email": email,
                "redirect_uri": redirect_uri,
                "state": state,
            }
        return code

    def consume_code(self, code):
        with self.lock:
            return self.auth_codes.pop(code, None)

    def save_refresh_token(self, refresh_token, email):
        with self.lock:
            self.refresh_tokens[refresh_token] = email

    def email_for_refresh_token(self, refresh_token):
        with self.lock:
            return self.refresh_tokens.get(refresh_token)

    def invalidate_refresh_token(self, refresh_token):
        with self.lock:
            self.refresh_tokens.pop(refresh_token, None)


STATE = MockState()


class MockAuthHandler(BaseHTTPRequestHandler):
    server_version = "MockAuthServer/1.0"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - - [%s] %s\n" % (
            self.client_address[0],
            self.log_date_time_string(),
            fmt % args,
        ))

    def do_HEAD(self):
        self.handle_request()

    def do_GET(self):
        self.handle_request()

    def do_POST(self):
        self.handle_request()

    def handle_request(self):
        parsed = urlparse(self.path)
        path = normalize_path(parsed.path)

        if path.startswith("/__admin/"):
            self.handle_admin(path)
            return

        queued = STATE.dequeue(self.command, path)
        if queued is not None:
            self.respond_with_spec(queued)
            return

        if path == "/test":
            self.send_text(200, "ok")
            return

        if self.command == "GET" and path == "/oauth/authorize":
            self.render_authorize_page(parse_qs(parsed.query))
            return

        if self.command == "GET" and path == "/embedded/continue":
            self.render_embedded_continue(parse_qs(parsed.query))
            return

        if self.command == "POST" and path == "/embedded/password":
            self.complete_embedded_password()
            return

        if self.command == "GET" and path == "/browser/complete":
            self.complete_browser_flow(parse_qs(parsed.query))
            return

        if self.command == "POST" and path == "/oauth/token":
            self.handle_oauth_token()
            return

        if self.command == "POST" and path == "/frontegg/oauth/authorize/silent":
            self.handle_silent_authorize()
            return

        if self.command == "GET" and path == "/identity/resources/users/v2/me":
            self.handle_me()
            return

        if self.command == "GET" and path == "/identity/resources/users/v3/me/tenants":
            self.handle_tenants()
            return

        if self.command == "POST" and path == "/oauth/logout/token":
            self.handle_logout()
            return

        self.send_json(404, {"error": f"Unhandled route {self.command} {path}"})

    def handle_admin(self, path):
        if self.command != "POST":
            self.send_json(405, {"error": "admin endpoints require POST"})
            return

        if path == "/__admin/reset":
            STATE.reset()
            self.send_json(200, {"ok": True})
            return

        if path == "/__admin/enqueue":
            body = self.read_json_body()
            STATE.enqueue(body["method"], body["path"], body["responses"])
            self.send_json(200, {"ok": True})
            return

        self.send_json(404, {"error": f"Unknown admin path {path}"})

    def render_authorize_page(self, query):
        redirect_uri = query.get("redirect_uri", [""])[0]
        state = query.get("state", [""])[0]
        login_action = query.get("login_direct_action", [""])[0]

        if login_action:
            action = decode_b64url_json(login_action)
            destination = (action or {}).get("data", "")
            if "custom-sso" in destination:
                title = "Custom SSO Mock Server"
                button = "Continue to Custom SSO"
                email = "custom-sso@frontegg.com"
            elif "mock-social-provider" in destination:
                title = "Mock Social Login"
                button = "Continue with Mock Social"
                email = "social-login@frontegg.com"
            else:
                title = "Direct Login Mock Server"
                button = "Continue"
                email = "direct-login@frontegg.com"

            params = urlencode({
                "email": email,
                "redirect_uri": redirect_uri,
                "state": state,
            })
            body = f"""
                <h1>{html.escape(title)}</h1>
                <form action="/browser/complete" method="get">
                  <input type="hidden" name="email" value="{html.escape(email)}" />
                  <input type="hidden" name="redirect_uri" value="{html.escape(redirect_uri)}" />
                  <input type="hidden" name="state" value="{html.escape(state)}" />
                  <button type="submit">{html.escape(button)}</button>
                </form>
            """
            self.send_html(200, title, body)
            return

        body = f"""
            <h1>Mock Embedded Login</h1>
            <form action="/embedded/continue" method="get">
              <input type="hidden" name="redirect_uri" value="{html.escape(redirect_uri)}" />
              <input type="hidden" name="state" value="{html.escape(state)}" />
              <input type="email" name="email" placeholder="Email is required" />
              <button type="submit">Continue</button>
            </form>
        """
        self.send_html(200, "Mock Embedded Login", body)

    def render_embedded_continue(self, query):
        email = query.get("email", ["test@frontegg.com"])[0]
        redirect_uri = query.get("redirect_uri", [""])[0]
        state = query.get("state", [""])[0]

        if email.endswith("@saml-domain.com"):
            self.send_html(
                200,
                "OKTA SAML Mock Server",
                f"""
                    <h1>OKTA SAML Mock Server</h1>
                    <form action="/browser/complete" method="get">
                      <input type="hidden" name="email" value="{html.escape(email)}" />
                      <input type="hidden" name="redirect_uri" value="{html.escape(redirect_uri)}" />
                      <input type="hidden" name="state" value="{html.escape(state)}" />
                      <button type="submit">Login With Okta</button>
                    </form>
                """,
            )
            return

        if email.endswith("@oidc-domain.com"):
            self.send_html(
                200,
                "OKTA OIDC Mock Server",
                f"""
                    <h1>OKTA OIDC Mock Server</h1>
                    <form action="/browser/complete" method="get">
                      <input type="hidden" name="email" value="{html.escape(email)}" />
                      <input type="hidden" name="redirect_uri" value="{html.escape(redirect_uri)}" />
                      <input type="hidden" name="state" value="{html.escape(state)}" />
                      <button type="submit">Login With Okta</button>
                    </form>
                """,
            )
            return

        self.send_html(
            200,
            "Password Login",
            f"""
                <h1>Password Login</h1>
                <form action="/embedded/password" method="post">
                  <input type="hidden" name="email" value="{html.escape(email)}" />
                  <input type="hidden" name="redirect_uri" value="{html.escape(redirect_uri)}" />
                  <input type="hidden" name="state" value="{html.escape(state)}" />
                  <input type="password" name="password" placeholder="Password is required" />
                  <button type="submit">Sign in</button>
                </form>
            """,
        )

    def complete_embedded_password(self):
        form = parse_qs(self.read_body().decode("utf-8"))
        email = form.get("email", ["test@frontegg.com"])[0]
        redirect_uri = form.get("redirect_uri", [""])[0]
        state = form.get("state", [""])[0]
        code = STATE.issue_code(email, redirect_uri, state)
        location = self.build_callback_url(redirect_uri, code, state)
        self.send_redirect(location)

    def complete_browser_flow(self, query):
        email = query.get("email", ["browser@frontegg.com"])[0]
        redirect_uri = query.get("redirect_uri", [""])[0]
        state = query.get("state", [""])[0]
        code = STATE.issue_code(email, redirect_uri, state)
        location = self.build_callback_url(redirect_uri, code, state)
        self.send_redirect(location)

    def handle_oauth_token(self):
        body = self.read_json_body()
        grant_type = body.get("grant_type")
        if grant_type == "authorization_code":
            code = body.get("code")
            if not code:
                self.send_json(400, {"error": "missing_code"})
                return
            auth_code = STATE.consume_code(code)
            if auth_code is None:
                self.send_json(400, {"error": "invalid_code"})
                return
            refresh_token = f"refresh-{uuid.uuid4()}"
            STATE.save_refresh_token(refresh_token, auth_code["email"])
            self.send_json(200, auth_response_for_email(auth_code["email"], refresh_token))
            return

        if grant_type == "refresh_token":
            refresh_token = body.get("refresh_token")
            email = STATE.email_for_refresh_token(refresh_token)
            if email is None:
                self.send_json(401, {"error": "invalid_refresh_token"})
                return
            self.send_json(200, auth_response_for_email(email, refresh_token))
            return

        self.send_json(400, {"error": f"unsupported_grant_type {grant_type}"})

    def handle_silent_authorize(self):
        refresh_token = None
        for chunk in self.headers.get("Cookie", "").split(";"):
            chunk = chunk.strip()
            if chunk.startswith("fe_refresh_") and "=" in chunk:
                refresh_token = chunk.split("=", 1)[1]
                break
        email = STATE.email_for_refresh_token(refresh_token) if refresh_token else None
        if email is None:
            self.send_json(401, {"error": "invalid_refresh_cookie"})
            return
        self.send_json(200, auth_response_for_email(email, refresh_token))

    def handle_me(self):
        email = self.email_from_authorization_header()
        if email is None:
            self.send_json(401, {"error": "missing_access_token"})
            return
        self.send_json(200, user_response(email))

    def handle_tenants(self):
        email = self.email_from_authorization_header()
        if email is None:
            self.send_json(401, {"error": "missing_access_token"})
            return
        tenant = tenant_response(email)
        self.send_json(200, {"tenants": [tenant], "activeTenant": tenant})

    def handle_logout(self):
        refresh_token = None
        for chunk in self.headers.get("Cookie", "").split(";"):
            chunk = chunk.strip()
            if chunk.startswith("fe_refresh_") and "=" in chunk:
                refresh_token = chunk.split("=", 1)[1]
                break
        if refresh_token:
            STATE.invalidate_refresh_token(refresh_token)
        self.send_json(200, {"ok": True})

    def email_from_authorization_header(self):
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return None
        token = auth.removeprefix("Bearer ").strip()
        try:
            payload = decode_b64url_json(token.split(".")[1])
        except Exception:
            return None
        return payload.get("email")

    def build_callback_url(self, redirect_uri, code, state):
        delimiter = "&" if "?" in redirect_uri else "?"
        return f"{redirect_uri}{delimiter}{urlencode({'code': code, 'state': state})}"

    def read_body(self):
        length = int(self.headers.get("Content-Length", "0"))
        return self.rfile.read(length) if length > 0 else b""

    def read_json_body(self):
        raw = self.read_body()
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def respond_with_spec(self, spec):
        delay_ms = int(spec.get("delay_ms", 0))
        if delay_ms > 0:
            time.sleep(delay_ms / 1000.0)

        if spec.get("close_connection"):
            self.close_connection = True
            return

        status = int(spec.get("status", 200))
        headers = dict(spec.get("headers", {}))
        redirect = spec.get("redirect")
        if redirect:
            headers["Location"] = redirect
            if "status" not in spec:
                status = 302

        body = b""
        if "json" in spec:
            body = json.dumps(spec["json"]).encode("utf-8")
            headers.setdefault("Content-Type", "application/json; charset=utf-8")
        elif "body" in spec:
            body = str(spec["body"]).encode("utf-8")

        if self.command == "HEAD":
            body = b""

        self.send_response(status)
        headers.setdefault("Content-Length", str(len(body)))
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def send_html(self, status, title, body):
        page = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{html.escape(title)}</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      padding: 32px 20px;
      background: #f7f7f8;
      color: #111;
    }}
    h1 {{
      font-size: 28px;
      margin: 0 0 16px 0;
    }}
    form {{
      display: flex;
      flex-direction: column;
      gap: 12px;
      max-width: 360px;
    }}
    input {{
      font-size: 16px;
      padding: 12px;
      border-radius: 10px;
      border: 1px solid #d0d5dd;
    }}
    button {{
      font-size: 16px;
      padding: 14px 18px;
      border: 0;
      border-radius: 12px;
      background: #0f62fe;
      color: white;
    }}
  </style>
</head>
<body>
  {body}
</body>
</html>"""
        encoded = page.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def send_text(self, status, body):
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(encoded)

    def send_json(self, status, payload):
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(encoded)

    def send_redirect(self, location):
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), MockAuthHandler)
    print(f"READY {server.server_address[1]}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
