#!/usr/bin/env python3
"""Prepare one official reference export for transactional staging."""

import argparse
import hashlib
import json
import re
from collections import defaultdict
from datetime import date, datetime
from pathlib import Path

SOURCES = {
    "school": (
        "https://data.education.gouv.fr/explore/dataset/fr-en-annuaire-education/",
        ("identifiant_de_l_etablissement", "nom_etablissement"),
    ),
    "closed": (
        "https://data.education.gouv.fr/explore/dataset/fr-en-etablissements-fermes/",
        ("numero_uai", "date_fermeture"),
    ),
    "higher": (
        "https://data.enseignementsup-recherche.gouv.fr/explore/dataset/fr-esr-principaux-etablissements-enseignement-superieur/",
        ("etablissement_id_paysage",),
    ),
}


def text(row, key, max_length):
    value = row.get(key)
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError("invalid_field_type")
    value = value.strip()
    if len(value) > max_length or any(ord(char) < 32 for char in value):
        raise ValueError("invalid_field_value")
    return value or None


def higher_kind(row):
    value = row.get("type_d_etablissement")
    if not isinstance(value, list):
        return text(row, "type_d_etablissement", 150)
    labels = {text({"label": label}, "label", 150) for label in value}
    return text({"kind": " / ".join(sorted(labels - {None}))}, "kind", 150)


def uai(row, key):
    value = text(row, key, 150)
    if value and re.fullmatch(r"[0-9]{7}[A-Za-z]", value):
        return value.upper()
    return None


def source_date(row, key):
    value = text(row, key, 40)
    if value is None:
        return None
    try:
        if "T" in value:
            return datetime.fromisoformat(value).date().isoformat()
        return date.fromisoformat(value).isoformat()
    except ValueError as error:
        raise ValueError("invalid_date") from error


def source_identifier(source, row):
    if source == "school":
        return uai(row, "identifiant_de_l_etablissement")
    if source == "closed":
        return uai(row, "numero_uai")
    return text(row, "etablissement_id_paysage", 150)


def normalize(source, row, identifier):
    official_uai = identifier
    source_status = None
    if source == "school":
        name = text(row, "nom_etablissement", 300)
        city, kind = text(row, "nom_commune", 150), text(row, "type_etablissement", 150)
        status = text(row, "etat", 80)
        source_status = status.upper() if status else None
        if source_status and len(source_status) > 80:
            raise ValueError("invalid_field_value")
    elif source == "closed":
        names = [text(row, key, 300) for key in ("appellation_officielle", "denomination_principale", "patronyme_uai")]
        name = next((name for name in names if name and name != "-"), None)
        city, kind = text(row, "libelle_commune", 150), text(row, "nature_uai_libe", 150)
    else:
        official_uai = uai(row, "uai")
        name = text(row, "uo_lib_officiel", 300) or text(row, "uo_lib", 300)
        city, kind = text(row, "com_nom", 150), higher_kind(row)
    if not name or name == "-":
        if source != "closed":
            raise ValueError("missing_name")
        name = None
    opened_on = source_date(row, "date_ouverture") if source == "closed" else None
    closed_on = source_date(row, "date_fermeture") if source == "closed" else None
    if source == "closed" and (not closed_on or (opened_on and opened_on > closed_on)):
        raise ValueError("invalid_closure_period")
    return {"external_id": identifier, "uai": official_uai, "name": name,
            "city": city, "kind": kind, "source_status": source_status,
            "opened_on": opened_on, "closed_on": closed_on,
            "needs_review": name is None}


def prepare(source, update, publisher, content):
    rows = json.loads(content)
    url, required = SOURCES[source]
    if not isinstance(rows, list) or not rows or not all(isinstance(row, dict) for row in rows):
        raise ValueError("expected_nonempty_json_export")
    fields = set().union(*(row.keys() for row in rows))
    if not set(required) <= fields or (
        source == "higher" and not fields.intersection({"uo_lib", "uo_lib_officiel"})
    ):
        raise ValueError("unexpected_source_schema")

    grouped = defaultdict(list)
    rejected = []
    invalid_identifiers = set()
    for number, row in enumerate(rows, start=1):
        identifier = None
        try:
            identifier = source_identifier(source, row)
            if not identifier:
                raise ValueError("missing_identifier")
            entry = normalize(source, row, identifier)
        except ValueError as error:
            rejection = {"row_number": number, "reason": str(error)}
            if identifier:
                rejection["external_id"] = identifier
                invalid_identifiers.add(identifier)
            rejected.append(rejection)
        else:
            grouped[identifier].append((number, entry))

    candidates = []
    duplicates = 0
    for identifier, matches in grouped.items():
        first = matches[0][1]
        if identifier in invalid_identifiers or any(candidate != first for _, candidate in matches):
            rejected.extend(
                {"row_number": number, "reason": "identifier_conflict", "external_id": entry["external_id"]}
                for number, entry in matches
            )
        else:
            candidates.append(first)
            duplicates += len(matches) - 1

    return {
        "source": source, "published_at": update, "publisher": publisher, "source_url": url,
        "sha256": hashlib.sha256(content).hexdigest(), "row_count": len(rows),
        "duplicates": duplicates, "candidates": candidates, "rejected": rejected,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", choices=SOURCES)
    parser.add_argument("export", type=Path)
    parser.add_argument("--published-at", required=True, help="Official ISO 8601 timestamp with timezone.")
    parser.add_argument("--publisher", required=True, help="Publisher shown in the official catalogue.")
    args = parser.parse_args()
    try:
        stamp = datetime.fromisoformat(args.published_at)
        if stamp.utcoffset() is None or not args.publisher.strip():
            raise ValueError("expected timestamp with timezone and nonempty publisher")
        payload = prepare(args.source, stamp.isoformat(), args.publisher.strip(), args.export.read_bytes())
    except (OSError, ValueError) as error:
        parser.exit(1, f"Import refusé ({args.source}) : {error}\n")
    print(json.dumps(payload, ensure_ascii=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
