#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
payload="$(mktemp)"
trap 'rm -f -- "$payload"' EXIT
python3 "$repo_root/scripts/prepare-directory-import.py" "$@" > "$payload"
printf 'begin;\ncreate temporary table directory_payload(body jsonb) on commit drop;\n'
printf 'copy directory_payload from stdin with (format csv, delimiter E\x27\\t\x27, quote E\x27\\x01\x27);\n'
cat "$payload"
printf '%s\n' '\.'
cat "$repo_root/supabase/import/stage-directory.sql"
