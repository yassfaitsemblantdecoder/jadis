#!/usr/bin/env python3
"""Run the private beta in Chromium against the disposable, local pilot gateway."""

import argparse
import json
import re
import secrets
import shutil
import time
from html.parser import HTMLParser
from urllib.error import URLError
from urllib.parse import parse_qs, quote, urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, build_opener

from playwright.sync_api import Error as BrowserError, expect, sync_playwright


class MailLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self.links.append(href)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def mail_client(origin):
    client = build_opener(ProxyHandler({}), NoRedirect())

    def fetch(path):
        with client.open(origin + "/__test/mail/api/v1/" + path, timeout=3) as response:
            return json.load(response)

    return fetch


def mail_ids(fetch):
    return {item["ID"] for item in fetch("messages")["messages"] or []}


def auth_email_link(fetch, origin, email, previous_ids, email_type):
    deadline = time.monotonic() + 20
    message = None
    while time.monotonic() < deadline:
        try:
            inbox = fetch("messages")["messages"] or []
            item = next((item for item in inbox
                         if item["ID"] not in previous_ids
                         and any(to["Address"].casefold() == email.casefold() for to in item["To"])), None)
            if item:
                message = fetch("message/" + quote(item["ID"], safe=""))
                break
        except (URLError, TimeoutError):
            pass
        time.sleep(0.25)
    if message is None:
        raise RuntimeError(f"No new {email_type} email reached the synthetic account in Mailpit")
    parser = MailLinks()
    parser.feed(message["HTML"])
    for href in parser.links:
        target = urlsplit(href)
        if (target.scheme, target.netloc, target.path) == (
            "http", urlsplit(origin).netloc, "/auth/v1/verify"
        ) and parse_qs(target.query).get("type") == [email_type]:
            return href
    raise RuntimeError(f"The {email_type} email did not contain the local verification endpoint")


def response_path(response, path, method="POST"):
    return response.request.method == method and urlsplit(response.url).path == path


def auth_failure(action, response):
    diagnostic = f"{action} returned HTTP {response.status}"
    try:
        code = response.json().get("error_code")
    except (AttributeError, BrowserError, ValueError):
        code = None
    if isinstance(code, str) and re.fullmatch(r"[a-z0-9_]{1,60}", code):
        diagnostic += f" ({code})"
    return RuntimeError(diagnostic)


def open_auth_email(page, link, beta_url):
    try:
        page.goto(link, wait_until="domcontentloaded")
        expect(page).to_have_url(beta_url)
    except (BrowserError, AssertionError):
        # The verification URL and its redirect can contain temporary credentials.
        raise RuntimeError("Mail verification did not return to beta.html with a clean URL") from None


def check_export(page, email, nickname, place, memory):
    with page.expect_download() as generated:
        page.locator("#download-data").click()
    download = generated.value
    if download.suggested_filename != "mes-donnees-jadis.json":
        raise RuntimeError("Unexpected account export filename")
    with download.path().open(encoding="utf-8") as contents:
        data = json.load(contents)
    timeline = data["timeline"]
    if (data["account"]["email"] != email or data["profile"]["display_name"] != nickname
            or len(timeline) != 1 or timeline[0]["place"] != place):
        raise RuntimeError("Export did not contain the synthetic account, profile and timeline entry")
    notices = data["saved_searches"]
    if (len(notices) != 1 or notices[0]["timeline_id"] != timeline[0]["id"]
            or notices[0]["memory_year"] != 2006):
        raise RuntimeError("Export did not contain the expected saved search")
    if [item["body"] for item in data["my_memories"]] != [memory]:
        raise RuntimeError("Export did not contain the expected capsule contribution")


def check(origin, email, invite):
    fetch = mail_client(origin)
    previous_ids = mail_ids(fetch)
    password = "Jadis-test-" + secrets.token_urlsafe(24)
    marker = secrets.token_hex(4)
    place = "Colonie fictive " + marker
    capsule_title = "Capsule fictive " + marker
    memory = "Une randonnée fictive."
    beta_url = origin + "/beta.html"
    expect.set_options(timeout=10_000)

    local_host = urlsplit(origin).hostname

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            executable_path=shutil.which("chromium"),
            args=["--disable-background-networking"],
            proxy={"server": "http://127.0.0.1:1", "bypass": "<-loopback>," + (
                "[::1]" if local_host == "::1" else local_host
            )},
        )
        context = browser.new_context(service_workers="block", accept_downloads=True)
        page = context.new_page()
        errors = []
        external = []

        gateway_origin = ("http", urlsplit(origin).netloc)

        def from_gateway(url):
            target = urlsplit(url)
            if target.scheme == "blob":
                target = urlsplit(target.path)
            return (target.scheme, target.netloc) == gateway_origin

        def on_request(request):
            if not from_gateway(request.url):
                external.append(urlsplit(request.url).hostname)

        def enforce_origin(route):
            if not from_gateway(route.request.url):
                route.abort()
                return
            route.continue_()

        context.on("request", on_request)
        context.route("**/*", enforce_origin)
        page.on("pageerror", lambda error: errors.append(error))

        page.goto(beta_url)
        expect(page.locator("#auth")).to_be_visible()
        expect(page.locator("#private")).to_be_hidden()
        page.locator("#toggle-signup").click()
        signup = page.locator("#signup")
        signup.locator("[name=email]").fill(email)
        signup.locator("[name=password]").fill(password)
        signup.locator("[name=adult]").check()
        with page.expect_response(lambda response: response_path(response, "/auth/v1/signup")) as created:
            signup.get_by_role("button", name="Créer mon compte").click()
        if not created.value.ok:
            raise auth_failure("Sign-up", created.value)
        expect(page.locator("#status")).to_contain_text("confirme ton adresse")
        open_auth_email(page, auth_email_link(fetch, origin, email, previous_ids, "signup"), beta_url)
        expect(page.locator("#auth")).to_be_visible()

        def login(secret, *, accepted=True):
            auth = page.locator("#auth")
            auth.locator("[name=email]").fill(email)
            auth.locator("[name=password]").fill(secret)
            with page.expect_response(lambda response: response_path(response, "/auth/v1/token")) as token:
                auth.get_by_role("button", name="Se connecter").click()
            if token.value.ok != accepted:
                raise auth_failure("Unexpected password login result", token.value)
            if not accepted:
                expect(page.locator("#status")).to_contain_text("Requête refusée")
                expect(page.locator("#private")).to_be_hidden()

        def logout():
            page.locator("#logout").click()
            expect(page.locator("#auth")).to_be_visible()
            expect(page.locator("#private")).to_be_hidden()

        login(password)
        invite_form = page.locator("#invite")
        expect(invite_form).to_be_visible()
        expect(page.locator("#private")).to_be_hidden()
        invite_form.locator("[name=code]").fill(invite)
        invite_form.locator("[name=adult]").check()
        invite_form.get_by_role("button", name="Activer mon accès").click()
        profile = page.locator("#profile")
        expect(profile).to_be_visible()
        nickname = "Profil fictif " + marker
        profile.locator("[name=name]").fill(nickname)
        profile.locator("[name=discoverable]").check()
        profile.get_by_role("button", name="Enregistrer mon profil").click()
        expect(page.locator("#status")).to_have_text("Profil enregistré.")

        timeline = page.locator("#timeline-entry")
        timeline.locator("[name=kind]").select_option("camp")
        timeline.locator("[name=place]").fill(place)
        timeline.locator("[name=city]").fill("Commune fictive")
        timeline.locator("[name=start_year]").fill("2005")
        timeline.locator("[name=end_year]").fill("2006")
        timeline.locator("[name=visible]").check()
        timeline.get_by_role("button", name="Ajouter à ma frise").click()
        expect(page.locator("#timeline-entries")).to_contain_text(place)
        search = page.locator("#memory-search")
        search.locator("[name=year]").fill("2006")
        search.get_by_role("button", name="Chercher les croisements").click()
        expect(page.locator("#memory-matches")).to_contain_text("Aucun croisement")
        search.get_by_role("button", name="Enregistrer cette recherche").click()
        expect(page.locator("#search-notice-list")).to_contain_text(place)
        expect(page.locator("#search-notice-list")).to_contain_text("2006")

        capsule = page.locator("#capsule-create")
        expect(capsule).to_be_visible()
        capsule.locator("[name=title]").fill(capsule_title)
        capsule.locator("[name=year]").fill("2006")
        capsule.get_by_role("button", name="Créer une capsule").click()
        created_capsule = page.locator("#capsule-list article").filter(has_text=capsule_title)
        created_capsule.get_by_role("button", name="Ouvrir la capsule").click()
        post = page.locator("#capsule-post")
        expect(post).to_be_visible()
        post.locator("[name=body]").fill(memory)
        post.get_by_role("button", name="Ajouter le souvenir").click()
        expect(page.locator("#capsule-archive")).to_contain_text(memory)

        logout()
        login(password)
        expect(profile.locator("[name=name]")).to_have_value(nickname)
        expect(page.locator("#timeline-entries")).to_contain_text(place)
        expect(page.locator("#search-notice-list")).to_contain_text(place)
        created_capsule.get_by_role("button", name="Ouvrir la capsule").click()
        expect(page.locator("#capsule-archive")).to_contain_text(memory)

        logout()
        previous_ids = mail_ids(fetch)
        page.locator("#toggle-recovery").click()
        recovery = page.locator("#recover")
        recovery.locator("[name=email]").fill(email)
        recovery.get_by_role("button", name="Envoyer le lien").click()
        expect(page.locator("#status")).to_contain_text("email de récupération")
        open_auth_email(page, auth_email_link(fetch, origin, email, previous_ids, "recovery"), beta_url)
        new_password = "Jadis-test-" + secrets.token_urlsafe(24)
        change = page.locator("#new-password")
        expect(change).to_be_visible()
        change.locator("[name=password]").fill(new_password)
        change.get_by_role("button", name="Mettre à jour le mot de passe").click()
        expect(page.locator("#status")).to_contain_text("Mot de passe mis à jour.")
        login(password, accepted=False)
        login(new_password)
        expect(profile.locator("[name=name]")).to_have_value(nickname)
        check_export(page, email, nickname, place, memory)

        page.locator("#account-removal summary").click()
        removal = page.locator("#delete-account")
        removal.locator("[name=password]").fill(new_password)
        removal.locator("[name=confirmation]").fill("SUPPRIMER")
        with page.expect_response(lambda response: response_path(response, "/auth/v1/token")) as proof:
            removal.get_by_role("button", name="Supprimer définitivement").click()
        if not proof.value.ok:
            raise auth_failure("Reauthentication for removal", proof.value)
        expect(page.locator("#status")).to_have_text("Compte supprimé.")
        expect(page.locator("#account-data")).to_be_hidden()
        login(new_password, accepted=False)

        if external or errors:
            raise RuntimeError(f"Chromium recorded {len(external)} off-origin requests and {len(errors)} script errors")
        browser.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base_url", help="Loopback HTTP origin of the pilot gateway")
    parser.add_argument("email", help="A unique address under a reserved .test domain")
    parser.add_argument("invitation", help="Unused invitation code seeded in the disposable database")
    args = parser.parse_args()
    origin = urlsplit(args.base_url)
    if (origin.scheme != "http" or origin.hostname not in {"127.0.0.1", "::1", "localhost"}
            or origin.username is not None or origin.path not in {"", "/"} or origin.query or origin.fragment):
        parser.error("base_url must be a loopback HTTP origin with no credentials or path")
    if not re.fullmatch(r"[^@\s]+@(?:[a-z0-9-]+\.)+test", args.email, re.IGNORECASE):
        parser.error("email must be a synthetic address under .test")
    check(f"http://{origin.netloc}", args.email, args.invitation)
    print("Chromium checks passed (signup, email confirmation, invitation, timeline, private search, capsule, recovery, export and account removal).")


if __name__ == "__main__":
    main()
