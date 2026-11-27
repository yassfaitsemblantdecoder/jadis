#!/usr/bin/env python3
"""Check a configured recipe target without creating accounts or changing data."""

import os
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def check(url, key, opener):
    target = urlsplit(url)
    local_http = target.scheme == "http" and target.hostname in ("localhost", "127.0.0.1")
    if (target.scheme != "https" and not local_http) or not target.hostname or target.username is not None \
            or target.path not in ("", "/") or target.query or target.fragment:
        raise ValueError("JADIS_SUPABASE_URL doit être une origine HTTPS ou une origine HTTP locale.")
    if not re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]+", key):
        raise ValueError("JADIS_SUPABASE_PUBLISHABLE_KEY doit contenir une clé publiable.")

    for path, expected, label in (
        ("/auth/v1/health", {200}, "Service Auth"),
        ("/rest/v1/beta_members?select=user_id&limit=0", {401, 403}, "Lecture anonyme des adhésions"),
    ):
        request = Request(url.rstrip("/") + path, headers={"apikey": key})
        try:
            with opener.open(request, timeout=10) as response:
                status = response.status
        except HTTPError as error:
            status = error.code
        if status not in expected:
            raise ValueError(f"{label} : HTTP {status}, contrôle non concluant.")
        print(f"{label} : HTTP {status}")


def main():
    url = os.environ.get("JADIS_SUPABASE_URL", "").strip()
    key = os.environ.get("JADIS_SUPABASE_PUBLISHABLE_KEY", "").strip()
    if not url or not key:
        print("Renseigner les deux variables de la recette isolée avant le contrôle.", file=sys.stderr)
        return 1
    try:
        check(url, key, build_opener(NoRedirect()))
    except (ValueError, URLError, TimeoutError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
