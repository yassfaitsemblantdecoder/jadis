#!/usr/bin/env python3
"""Check the public API in the disposable PostgREST test environment."""

import base64
import hashlib
import hmac
import json
import os
import time
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, Request, build_opener


def encode(payload):
    return base64.urlsafe_b64encode(payload).rstrip(b"=")


def jwt(subject, secret):
    header = encode(b'{"alg":"HS256","typ":"JWT"}')
    claims = encode(json.dumps({
        "role": "authenticated", "sub": subject, "exp": int(time.time()) + 300,
    }).encode())
    token = header + b"." + claims
    return (token + b"." + encode(hmac.digest(secret, token, hashlib.sha256))).decode()


def main():
    base = "http://api:3000"
    opener = build_opener(ProxyHandler({}))
    secret = os.environ["PGRST_JWT_SECRET"].encode()
    owner, peer, nonmember = [f"00000000-0000-4000-8000-00000000000{n}" for n in (1, 2, 3)]

    def call(path, token=None, *, method="GET", headers=None, body=None):
        request_headers = dict(headers or {})
        if token:
            request_headers["Authorization"] = f"Bearer {token}"
        data = json.dumps(body if body is not None else {}).encode() if method == "POST" else None
        if data:
            request_headers["Content-Type"] = "application/json"
        req = Request(base + path, data=data, headers=request_headers, method=method)
        try:
            with opener.open(req, timeout=2) as response:
                payload = response.read()
                return response.status, json.loads(payload) if payload else None
        except HTTPError as error:
            payload = error.read()
            return error.code, json.loads(payload) if payload else None

    for attempt in range(30):
        try:
            status, _ = call("/")
            if status == 200:
                break
        except (URLError, TimeoutError):
            pass
        time.sleep(1)
    else:
        raise RuntimeError("PostgREST did not become ready")

    entries = "/beta_school_entries?select=user_id"
    assert call(entries)[0] in (401, 403), "Anonymous role can read entries"
    assert call(entries, jwt(nonmember, secret)) == (200, []), "Nonmember can read entries"
    assert call(entries, jwt(owner, secret)) == (200, [{"user_id": owner}]), "Owner visibility incorrect"
    assert call(entries, jwt(peer, secret)) == (200, [{"user_id": peer}]), "Peer visibility incorrect"

    discovery = "/rpc/beta_discover"
    assert call(discovery, method="POST")[0] in (401, 403, 404), "Anonymous discovery available"
    assert call(discovery, jwt(nonmember, secret), method="POST") == (200, []), "Nonmember discovers peers"
    status, rows = call(discovery, jwt(owner, secret), method="POST")
    assert status == 200 and [row["person_id"] for row in rows] == [peer], "Expected one consenting peer"

    status, _ = call("/directory_import_batches", jwt(owner, secret),
                     headers={"Accept-Profile": "jadis_private"})
    assert status == 406, "Private schema accepted through REST"
    owner_token, peer_token = jwt(owner, secret), jwt(peer, secret)

    def reconnect(token, action, **arguments):
        return call("/rpc/beta_reconnect", token, method="POST",
                    body={"action": action, **arguments})

    result = reconnect(owner_token, "request", target=peer)
    assert result == (200, {"ok": True}), result
    status, requests = reconnect(peer_token, "list")
    assert status == 200 and len(requests) == 1 and requests[0]["status"] == "pending"
    thread = requests[0]["id"]
    assert reconnect(peer_token, "accept", thread=thread) == (200, {"ok": True})
    assert reconnect(owner_token, "send", thread=thread, content="Message fictif") == (200, {"ok": True})
    status, messages = reconnect(peer_token, "messages", thread=thread)
    assert status == 200 and [message["body"] for message in messages] == ["Message fictif"]

    assert call("/blocks", peer_token, method="POST", body={"owner": peer, "target": owner})[0] == 201
    assert reconnect(owner_token, "list") == (200, [])
    assert reconnect(peer_token, "list") == (200, [])
    print("PostgREST checks passed.")


if __name__ == "__main__":
    main()
