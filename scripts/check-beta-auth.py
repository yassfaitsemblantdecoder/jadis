#!/usr/bin/env python3
"""Use real Auth tokens and a local mail sink on the disposable Docker network."""

import html
import json
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

AUTH = "http://auth:9999"
API = "http://api:3000"
MAIL = "http://mail:8025"


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


opener = build_opener(ProxyHandler({}), NoRedirect())


def call(url, *, data=None, token=None, method=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(url, headers=headers, method=method,
                      data=json.dumps(data).encode() if data is not None else None)
    try:
        response = opener.open(request, timeout=3)
    except HTTPError as error:
        response = error
    with response:
        if response.status in (302, 303):
            return response.status, response.headers["Location"]
        payload = response.read()
        if not payload or response.status >= 400:
            return response.status, None
        return response.status, json.loads(payload)


def wait_for(url, ready):
    for _ in range(30):
        try:
            status, result = call(url)
            if status == 200 and ready(result):
                return result
        except (URLError, TimeoutError):
            pass
        time.sleep(1)
    raise RuntimeError(f"Service readiness timed out at {url}")


def mail_ids():
    _, inbox = call(MAIL + "/api/v1/messages")
    return {message["ID"] for message in inbox["messages"] or []}


def verify_new_email(previous_messages):
    inbox = wait_for(MAIL + "/api/v1/messages",
                     lambda body: any(msg["ID"] not in previous_messages for msg in body["messages"] or []))
    message_id = next(msg["ID"] for msg in inbox["messages"] if msg["ID"] not in previous_messages)
    status, message = call(MAIL + "/api/v1/message/" + message_id)
    assert status == 200
    match = re.search(r'http://auth:9999/verify\?[^"\s<]+', html.unescape(message["HTML"]))
    assert match, "Verification link missing from isolated mail"
    status, location = call(match.group())
    assert status in (302, 303), "Email verification did not redirect"
    params = parse_qs(urlsplit(location).fragment)
    assert "access_token" in params, "Email verification did not establish a session"
    return params["access_token"][0]


def main():
    wait_for(AUTH + "/health", bool)
    wait_for(API + "/", bool)
    credentials = {"email": "pilote-jadis@example.test", "password": "Fixture-Jadis-passphrase-42!"}
    status, signup = call(AUTH + "/signup", data=credentials)
    assert status == 200 and "access_token" not in signup, status

    password_url = AUTH + "/token?grant_type=password"
    status, _ = call(password_url, data=credentials)
    assert status in (400, 401, 422), "Password login worked before email confirmation"

    verify_new_email(set())

    status, session = call(password_url, data=credentials)
    assert status == 200 and session["user"]["email_confirmed_at"], status
    token = session["access_token"]
    member = session["user"]["id"]
    assert call(API + "/beta_members?select=user_id", token=token) == (200, [])
    invite = {"code": "JADIS-TEST-INVITE", "adult": True}
    assert call(API + "/rpc/beta_redeem_invite", token=token, data=invite) == (200, True)
    assert call(API + "/beta_members?select=user_id", token=token) == (200, [{"user_id": member}])

    refreshed = {"refresh_token": session["refresh_token"]}
    refresh_url = AUTH + "/token?grant_type=refresh_token"
    status, renewed = call(refresh_url, data=refreshed)
    assert status == 200 and renewed["refresh_token"] != refreshed["refresh_token"]
    status, _ = call(AUTH + "/logout?scope=global", data={}, token=renewed["access_token"])
    assert status == 204, status
    status, _ = call(refresh_url, data={"refresh_token": renewed["refresh_token"]})
    assert status in (400, 401, 403), "Refresh remained available after logout"
    previous_messages = mail_ids()
    other = {**credentials, "email": "autre-jadis@example.test"}
    status, _ = call(AUTH + "/signup", data=other)
    assert status == 200, status
    nonmember_token = verify_new_email(previous_messages)
    assert call(API + "/rpc/beta_redeem_invite", token=nonmember_token, data=invite) == (200, False)
    assert call(API + "/beta_members?select=user_id", token=nonmember_token) == (200, [])

    previous_messages = mail_ids()
    status, _ = call(AUTH + "/recover", data={"email": credentials["email"]})
    assert status == 200, status
    recovery_token = verify_new_email(previous_messages)
    account_endpoint = API + "/rpc/beta_account_data"
    assert call(account_endpoint, token=recovery_token, data={"action":"delete","confirm":True})[0] >= 400
    new_password = "Fixture-Jadis-recovered-43!"
    status, _ = call(AUTH + "/user", token=recovery_token, method="PUT", data={"password": new_password})
    assert status == 200, status
    assert call(password_url, data=credentials)[0] in (400, 401, 422), "Old password remains valid"
    status, current_session = call(password_url, data={**credentials, "password": new_password})
    assert status == 200, status
    current_token = current_session["access_token"]
    assert call(API + "/profiles", token=current_token, data={"id":member,"display_name":"Compte fictif"})[0] == 201
    event = {"kind":"camp","place":"Colonie fictive","city":"Commune fictive","start_year":2005,"end_year":2006}
    status, row = call(API + "/rpc/beta_timeline", token=current_token, data={"action":"save","details":event})
    assert status == 200, status
    status, exported = call(account_endpoint, token=current_token, data={"action":"export"})
    assert status == 200 and exported["account"]["email"] == credentials["email"]
    assert [item["id"] for item in exported["timeline"]] == [row["id"]]
    status, other_export = call(account_endpoint, token=nonmember_token, data={"action":"export"})
    assert status == 200 and other_export["account"]["email"] == other["email"] and not other_export["timeline"]
    assert call(account_endpoint, token=current_token, data={"action":"delete"})[0] >= 400
    assert call(account_endpoint, token=current_token, data={"action":"delete","confirm":True}) == (200, {"deleted":True})
    assert call(account_endpoint, token=current_token, data={"action":"export"})[0] >= 400
    assert call(API + "/rpc/beta_timeline", token=current_token, data={"action":"list"})[0] >= 400
    assert call(password_url, data={**credentials,"password":new_password})[0] in (400, 401, 422)
    print("Supabase Auth, confirmation, single-use invitation, logout, password recovery, data export and account removal checks passed.")


if __name__ == "__main__":
    main()
