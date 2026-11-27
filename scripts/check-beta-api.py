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
    check_timeline(call, secret, jwt(nonmember, secret))
    print("PostgREST checks passed.")


def check_timeline(call, secret, nonmember_token):
    subjects = [f"00000000-0000-4000-8000-00000000000{n}" for n in (4, 5, 6)]
    owner, peer, outsider = [jwt(subject, secret) for subject in subjects]

    def rpc(name, token, **details):
        return call("/rpc/" + name, token, method="POST", body=details)

    assert rpc("beta_timeline", nonmember_token, action="list")[0] >= 400
    assert rpc("beta_timeline", None, action="list")[0] >= 400
    event = {"kind": "camp", "place": "Colonie fictive", "city": "Commune fictive",
             "start_year": 2003, "end_year": 2007}
    status, original = rpc("beta_timeline", owner, action="save", details=event)
    assert status == 200 and original["visible"] is False and "user_id" not in original, (status, original)
    entry_id = original["id"]
    assert rpc("beta_timeline", peer, action="list") == (200, [])
    assert rpc("beta_timeline", peer, action="delete", entry_id=entry_id) == (200, {"saved": False})
    assert rpc("beta_timeline", peer, action="save", entry_id=entry_id, details=event)[0] >= 400
    assert rpc("beta_timeline_crossings", owner, entry_id=entry_id) == (200, [])

    shared = {**event, "visible": True}
    assert rpc("beta_timeline", owner, action="save", entry_id=entry_id, details=shared)[0] == 200
    assert rpc("beta_timeline", peer, action="save",
               details={**shared, "place": "  COLONIE  fictive", "start_year": 2005, "end_year": 2010})[0] == 200
    assert rpc("beta_timeline", outsider, action="save", details={**shared, "city": "Autre commune"})[0] == 200
    assert rpc("beta_timeline_crossings", owner, entry_id=entry_id, memory_year=2010) == (200, [])
    status, rows = rpc("beta_timeline_crossings", owner, entry_id=entry_id, memory_year=2006)
    assert status == 200 and rows == [{
        "person_id": subjects[1], "display_name": "Personne fictive 5",
        "first_common_year": 2005, "last_common_year": 2007,
    }], (status, rows)

    assert rpc("beta_reconnect", owner, action="request", target=subjects[2])[0] >= 400
    assert rpc("beta_reconnect", owner, action="request", target=subjects[1]) == (200, {"ok": True})
    status, requests = rpc("beta_reconnect", peer, action="list")
    assert status == 200 and len(requests) == 1
    assert rpc("beta_reconnect", peer, action="accept", thread=requests[0]["id"]) == (200, {"ok": True})
    assert rpc("beta_search_notices", peer, action="save", entry_id=entry_id, memory_year=2006)[0] >= 400
    for _ in range(2):
        assert rpc("beta_search_notices", owner, action="save", entry_id=entry_id,
                   memory_year=2006) == (200, {"saved": True})
    status, notices = rpc("beta_search_notices", owner, action="list")
    assert status == 200 and len(notices) == 1 and notices[0]["available"] and notices[0]["memory_year"] == 2006
    assert rpc("beta_search_notices", peer, action="list") == (200, [])
    assert rpc("beta_search_notices", peer, action="delete", notice_id=notices[0]["id"]) == (200, {"saved": False})
    check_capsules(rpc, call, (owner, peer, outsider), subjects, entry_id)
    assert rpc("beta_timeline", owner, action="delete", entry_id=entry_id) == (200, {"saved": True})
    assert rpc("beta_timeline", owner, action="list") == (200, [])
    assert rpc("beta_search_notices", owner, action="list") == (200, [])
    print("Private timeline, memory matching and cross-category reconnection checks passed.")


def check_capsules(rpc, call, actors, subjects, entry_id):
    owner, peer, outsider = actors
    status, created = rpc("beta_capsules", owner, action="create",
                          details={"entry_id": entry_id, "year": 2006, "title": "Vacances fictives"})
    assert status == 200, status
    capsule_id = created["id"]

    def capsule(actor, action, details=None):
        return rpc("beta_capsules", actor, action=action, capsule_id=capsule_id, details=details)

    assert capsule(outsider, "list") == (200, [])
    assert capsule(outsider, "read")[0] >= 400
    assert capsule(owner, "invite", {"member_id": subjects[2]})[0] >= 400
    assert capsule(owner, "invite", {"member_id": subjects[1]}) == (200, {"ok": True})
    status, invitations = capsule(peer, "list")
    assert status == 200 and len(invitations) == 1 and not invitations[0]["joined"]
    assert capsule(peer, "read")[0] >= 400
    assert capsule(peer, "join") == (200, {"ok": True})
    status, posted = capsule(peer, "post", {"body": "Une randonnée fictive"})
    assert status == 200
    assert capsule(owner, "remove", {"memory_id": posted["id"]}) == (200, {"ok": False})
    status, memories = capsule(owner, "read")
    assert status == 200 and [row["body"] for row in memories] == ["Une randonnée fictive"]
    def photo(actor, action, details=None):
        return rpc("beta_capsule_photos", actor, action=action, capsule_id=capsule_id, details=details)

    image = {"body": "Carré fictif", "width": 1, "height": 1, "pixels": "/wAA"}
    assert photo(outsider, "post", image)[0] >= 400
    assert photo(peer, "post", {**image, "width": 193})[0] >= 400
    status, attachment = photo(peer, "post", image)
    assert status == 200, (status, attachment)
    photo_id = attachment["id"]
    assert photo(owner, "list") == (200, [photo_id])
    assert photo(owner, "read", {"memory_id": photo_id}) == (200, {
        key: value for key, value in image.items() if key != "body"
    })
    assert photo(outsider, "read", {"memory_id": photo_id})[0] >= 400
    assert capsule(peer, "leave") == (200, {"ok": True})
    assert capsule(owner, "read") == (200, [])
    assert photo(owner, "list") == (200, [])
    assert capsule(peer, "read")[0] >= 400
    assert capsule(owner, "invite", {"member_id": subjects[1]}) == (200, {"ok": True})
    assert capsule(peer, "join") == (200, {"ok": True})
    assert call("/blocks", peer, method="POST",
                body={"owner": subjects[1], "target": subjects[0]})[0] == 201
    assert capsule(peer, "read")[0] >= 400
    assert capsule(peer, "list") == (200, [])
    assert capsule(owner, "leave") == (200, {"ok": True})
    assert capsule(owner, "list") == (200, [])
    print("Invite-only capsules, private text and photo archive, blocking and removal checks passed.")


if __name__ == "__main__":
    main()
