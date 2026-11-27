#!/usr/bin/env python3
"""Probe public catalogues without writing or printing individual records."""

import argparse
import gzip
import json
import re
import sys
from itertools import combinations
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen

SOURCES = (
    ("school", "data.education.gouv.fr", "fr-en-annuaire-education"),
    ("closed", "data.education.gouv.fr", "fr-en-etablissements-fermes"),
    (
        "higher",
        "data.enseignementsup-recherche.gouv.fr",
        "fr-esr-principaux-etablissements-enseignement-superieur",
    ),
)
EXPECTED_FIELDS = {
    "school": (("identifiant_de_l_etablissement",), ("nom_etablissement",)),
    "closed": (("numero_uai",), ("date_fermeture",), ("date_ouverture",)),
    "higher": (("uai", "etablissement_id_paysage"), ("uo_lib", "uo_lib_officiel")),
}

EXPORT_FIELDS = {
    "school": ("identifiant_de_l_etablissement",),
    "closed": ("numero_uai",),
    "higher": ("uai", "etablissement_id_paysage"),
}


def fetch_json(url):
    with urlopen(url, timeout=12) as response:
        payload = response.read()
        if response.headers.get("Content-Encoding") == "gzip" or payload.startswith(b"\x1f\x8b"):
            payload = gzip.decompress(payload)
        return json.loads(payload)


def sample_identifier(source, row):
    if source == "school":
        identifier = row.get("identifiant_de_l_etablissement")
    elif source == "closed":
        identifier = row.get("numero_uai")
    else:
        identifier = row.get("uai")
        if not re.fullmatch(r"[0-9]{7}[A-Z]", str(identifier or ""), re.I):
            paysage = row.get("etablissement_id_paysage")
            return f"paysage:{paysage}" if paysage else None
    if re.fullmatch(r"[0-9]{7}[A-Z]", str(identifier or ""), re.I):
        return f"uai:{identifier.upper()}"
    return None


def check_source(source, host, dataset, fetch=fetch_json):
    endpoint = f"https://{host}/api/explore/v2.1/catalog/datasets/{dataset}"
    catalogue = fetch(endpoint)
    records = []
    total = None
    for offset in (0, 5):
        query = urlencode({"limit": 5, "offset": offset})
        page = fetch(f"{endpoint}/records?{query}")
        total = page["total_count"]
        records.extend(page["results"])

    fields = {field["name"] for field in catalogue["fields"]}
    metas = catalogue["metas"]["default"]
    license_metadata = metas.get("license") or metas.get("license_url")
    identifiers = [identifier for row in records if (identifier := sample_identifier(source, row)) is not None]
    missing = ["/".join(group) for group in EXPECTED_FIELDS[source] if not fields.intersection(group)]
    report = {
        "source": source,
        "catalogue": endpoint,
        "licence_declaree": license_metadata,
        "source_publiee_par": metas.get("publisher"),
        "derniere_mise_a_jour": metas.get("modified"),
        "total_annonce": total,
        "lignes_echantillonnees": len(records),
        "identifiants_reconnus": len(identifiers),
        "identifiants_repetes": len(identifiers) - len(set(identifiers)),
        "champs_obligatoires_absents": missing,
        "champs_disponibles": sorted(fields),
    }
    return report, bool(license_metadata and records and identifiers and not missing)


def export_profile(source, endpoint):
    fields = EXPORT_FIELDS[source]
    query = urlencode({"select": ",".join(fields)})
    records = fetch_json(f"{endpoint}/exports/json?{query}")
    if not isinstance(records, list) or any(set(row) - set(fields) for row in records):
        raise ValueError("Projection des identifiants non respectée")
    report = {"source": source, "lignes_exportees": len(records)}
    uai_values = set()
    for index, field in enumerate(fields):
        values = [str(row.get(field) or "").strip() for row in records]
        if index == 0:
            values = [value.upper() for value in values]
        suffix = "uai" if index == 0 else "paysage"
        report[f"{suffix}_manquants"] = values.count("")
        distinct = set(values) - {""}
        report[f"{suffix}_distincts"] = len(distinct)
        if index == 0:
            uai_values = {value for value in distinct if re.fullmatch(r"[0-9]{7}[A-Z]", value)}
            report["uai_format_inattendu"] = len(distinct - uai_values)
    return report, uai_values


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("--exports", action="store_true", help="Comparer les identifiants dans les exports complets.")
    settings = args.parse_args()
    passed = True
    uai_by_source = {}
    for source, host, dataset in SOURCES:
        try:
            report, ok = check_source(source, host, dataset)
            if settings.exports and ok:
                profile, uai_by_source[source] = export_profile(source, report["catalogue"])
                report["export"] = profile
                ok = profile["lignes_exportees"] == report["total_annonce"]
        except (HTTPError, URLError, TimeoutError, ValueError, KeyError, TypeError, gzip.BadGzipFile, EOFError) as error:
            report = {"source": source, "erreur": str(error)}
            ok = False
        print(json.dumps(report, ensure_ascii=False))
        passed &= ok
    for left, right in combinations(uai_by_source, 2):
        overlap = len(uai_by_source[left] & uai_by_source[right])
        print(json.dumps({"sources_comparees": [left, right], "uai_communs": overlap}))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
