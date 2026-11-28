#!/usr/bin/env python3
"""Serve the synthetic pilot build and forward requests to its internal services."""

import argparse
import base64
import json
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import BoundedSemaphore
from urllib.parse import urlsplit


STATIC_FILES = {
    "index.html", "beta.html", "style.css", "app.js", "beta.js", "beta-config.js",
    "matching.js", "directory.js", "classes.js", "timeline.js", "capsules.js", "pilot-school.js",
}
STATIC_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
}
REQUEST_HEADERS = (
    "Accept", "Accept-Profile", "Authorization", "apikey", "Content-Profile",
    "Content-Type", "Prefer", "Range", "Range-Unit",
)
MAX_REQUEST = 1024 * 1024
MAX_RESPONSE = 8 * 1024 * 1024

# Each invocation uses the test container's DNS and never follows a redirect.
PROBE = r"""
import base64
import json
import sys
from urllib.error import HTTPError
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

origins = {'auth': 'http://auth:9999', 'api': 'http://api:3000', 'mail': 'http://mail:8025'}
allowed_headers = ('Content-Type', 'Content-Range', 'Location', 'Preference-Applied', 'WWW-Authenticate')

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

details = json.load(sys.stdin)
opener = build_opener(ProxyHandler({}), NoRedirect())
request = Request(origins[details['service']] + details['target'],
                  data=base64.b64decode(details['body']) if details['body'] is not None else None,
                  headers=details['headers'], method=details['method'])
try:
    response = opener.open(request, timeout=8)
except HTTPError as error:
    response = error
with response:
    body = response.read(details['limit'] + 1)
    if len(body) > details['limit']:
        raise SystemExit(1)
    headers = {name: response.headers[name] for name in allowed_headers if name in response.headers}
    print(json.dumps({'status': response.status, 'headers': headers,
                      'body': base64.b64encode(body).decode('ascii')}))
"""


def load_assets(root):
    assets = {}
    for filename in STATIC_FILES:
        path = root / filename
        if path.is_symlink():
            raise ValueError("Invalid static asset.")
        if path.is_file():
            if path.stat().st_size > MAX_RESPONSE:
                raise ValueError("Static asset exceeds the size limit.")
            assets["/" + filename] = (STATIC_TYPES[path.suffix], path.read_bytes())
    if "/index.html" not in assets:
        raise ValueError("The static build must contain index.html.")
    assets["/"] = assets["/index.html"]
    return assets


def docker_output(args):
    return subprocess.check_output(["docker", *args], stderr=subprocess.DEVNULL, timeout=10)


def check_probe(container):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}", container):
        raise ValueError("Invalid probe container name or ID.")
    template = '{{json .NetworkSettings.Networks}}'
    networks = json.loads(docker_output(["inspect", "--type", "container", "--format", template, container]))
    if not networks or any(
        docker_output(["network", "inspect", "--format", "{{.Internal}}", settings["NetworkID"]]).strip() != b"true"
        for settings in networks.values()
    ):
        raise ValueError("The probe must use an internal Docker network.")


def find_backend(path):
    for prefix, service in (("/auth/v1", "auth"), ("/rest/v1", "api")):
        if path == prefix or path.startswith(prefix + "/"):
            target = path[len(prefix):] or "/"
            if re.fullmatch(r"/(?:[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*/?)?", target):
                return service, target
    prefix = "/__test/mail"
    if path == prefix + "/api/v1/messages" or re.fullmatch(
        prefix + r"/api/v1/message/[A-Za-z0-9_-]{1,128}", path
    ):
        return "mail", path[len(prefix):]
    return None


class Gateway(ThreadingHTTPServer):
    def __init__(self, port, assets, probe):
        self.assets = assets
        self.probe = probe
        self.slots = BoundedSemaphore(8)
        self.hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
        super().__init__(("127.0.0.1", port), Handler)

    def handle_error(self, request, client_address):
        return


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def setup(self):
        self.request.settimeout(10)
        super().setup()

    def log_message(self, *args):
        return

    def send_error(self, code, message=None, explain=None):
        self.reply(code, {"Content-Type": "text/plain; charset=utf-8"}, b"Request unavailable.\n")

    def reply(self, status, headers, body):
        if status in (204, 304):
            body = b""
        self.send_response(status)
        for name, value in headers.items():
            if "\r" not in value and "\n" not in value:
                self.send_header(name, value)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD" and body:
            self.wfile.write(body)

    def dispatch(self):
        host = self.headers.get_all("Host", [])
        if len(host) != 1 or host[0] not in self.server.hosts:
            self.send_error(403)
            return
        origin = self.headers.get_all("Origin", [])
        if (origin and origin != ["http://" + host[0]]) or self.headers.get("Sec-Fetch-Site") == "cross-site":
            self.send_error(403)
            return
        if not self.path.startswith("/") or self.path.startswith("//") or len(self.path) > 8192:
            self.send_error(400)
            return
        path = urlsplit(self.path)
        if path.netloc or path.scheme or path.fragment:
            self.send_error(400)
            return
        asset = self.server.assets.get(path.path)
        if asset:
            if self.command in ("GET", "HEAD"):
                media_type, body = asset
                self.reply(200, {"Content-Type": media_type}, body)
            else:
                self.send_error(405)
            return
        backend = find_backend(path.path)
        if not backend:
            self.send_error(404)
            return
        service, target = backend
        if service == "mail" and self.command != "GET":
            self.send_error(405)
            return
        if path.query:
            target += "?" + path.query
        if not self.server.slots.acquire(blocking=False):
            self.send_error(503)
            return
        try:
            self.relay(service, target)
        finally:
            self.server.slots.release()

    def relay(self, service, target):
        lengths = self.headers.get_all("Content-Length", [])
        if "Transfer-Encoding" in self.headers or len(lengths) > 1 or (
            lengths and not re.fullmatch(r"[0-9]{1,10}", lengths[0])
        ):
            self.send_error(400)
            return
        size = int(lengths[0]) if lengths else 0
        if size > MAX_REQUEST:
            self.send_error(413)
            return
        body = self.rfile.read(size) if lengths else None
        if body is not None and len(body) != size:
            self.send_error(400)
            return
        headers = {} if service == "mail" else {
            name: self.headers[name] for name in REQUEST_HEADERS if name in self.headers
        }
        try:
            command = ["docker", "exec", "-i", self.server.probe, "python", "-c", PROBE]
            descriptor = dict(service=service, target=target, method=self.command, headers=headers,
                              limit=MAX_RESPONSE, body=base64.b64encode(body).decode("ascii") if body is not None else None)
            output = subprocess.check_output(command, input=json.dumps(descriptor).encode("utf-8"),
                                             stderr=subprocess.DEVNULL, timeout=12)
            response = json.loads(output)
            payload = base64.b64decode(response["body"], validate=True)
        except (subprocess.SubprocessError, OSError, ValueError, KeyError):
            self.send_error(502)
            return
        self.reply(response["status"], response["headers"], payload)

    do_GET = do_HEAD = do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = dispatch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", type=int)
    parser.add_argument("static_dir", type=Path)
    parser.add_argument("probe_container")
    options = parser.parse_args()
    if not 1 <= options.port <= 65535:
        parser.error("port must be between 1 and 65535")
    try:
        check_probe(options.probe_container)
        with Gateway(options.port, load_assets(options.static_dir), options.probe_container) as server:
            server.serve_forever()
    except KeyboardInterrupt:
        return
    except (subprocess.SubprocessError, OSError, ValueError, KeyError):
        parser.exit(1, "Could not start the local pilot gateway.\n")


if __name__ == "__main__":
    main()
