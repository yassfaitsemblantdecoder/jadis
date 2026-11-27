#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
image=postgres:16@sha256:ce81150802644ddfac1db4da9e63be6f2a3818aa6ee98a7a28838aeea65dc37a
container=
api_container=
network=
cleanup() {
  if [[ -n "$api_container" ]]; then docker stop "$api_container" >/dev/null; fi
  if [[ -n "$container" ]]; then docker stop "$container" >/dev/null; fi
  if [[ -n "$network" ]]; then docker network rm "$network" >/dev/null; fi
}
trap cleanup EXIT

database_network=(--network none)
if [[ "${1:-}" == --rest ]]; then
  network="$(docker network create --internal "jadis-test-$$")"
  database_network=(--network "$network" --network-alias database)
fi
container="$(docker run --detach --rm "${database_network[@]}" \
  --tmpfs /var/lib/postgresql/data \
  --env POSTGRES_HOST_AUTH_METHOD=trust "$image")"

ready=false
for ((attempt = 0; attempt < 60; attempt++)); do
  # The temporary initialization server has no TCP listener.
  if docker exec "$container" pg_isready -h 127.0.0.1 -U postgres -q; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  docker logs "$container" >&2
  exit 1
fi

psql() {
  docker exec -i "$container" psql -X -v ON_ERROR_STOP=1 -U postgres "$@"
}

psql < supabase/tests/bootstrap.sql
for migration in supabase/migrations/*.sql; do
  printf 'Applying %s\n' "$migration"
  psql < "$migration"
done
psql < supabase/tests/foundation.sql

stage_fixture() {
  local source="$1"
  bash scripts/directory-stage-sql.sh "$source" "supabase/tests/fixtures/directory-$source.json" \
    --published-at 2026-01-01T00:00:00Z --publisher "Éditeur fictif" | psql
}

# A schema from another source must fail before the runner emits SQL.
if bash scripts/directory-stage-sql.sh school supabase/tests/fixtures/directory-higher.json \
    --published-at 2026-01-01T00:00:00Z --publisher "Éditeur fictif" > /dev/null; then
  printf '%s\n' 'Wrong source schema was accepted' >&2
  exit 1
fi

# Race two copies of the same snapshot, then exercise the other sources.
stage_fixture school &
first_stage=$!
stage_fixture school &
second_stage=$!
wait "$first_stage"
wait "$second_stage"
stage_fixture closed
stage_fixture higher
psql < supabase/tests/directory-staging.sql

printf 'Restoring and retesting the migrated database
'
docker exec "$container" createdb -U postgres foundation_restore
docker exec "$container" pg_dump -U postgres --no-password postgres |
  psql --quiet -d foundation_restore
psql -d foundation_restore < supabase/tests/foundation.sql
psql -d foundation_restore < supabase/tests/directory-staging.sql

if [[ "${1:-}" == --rest ]]; then
  psql < supabase/tests/api-fixtures.sql
  export PGRST_JWT_SECRET
  PGRST_JWT_SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
  api_image=postgrest/postgrest:v12.2.12@sha256:5f4ce744539bbba786b4e24dbbd95bdb2a956dcf568c5374995a0ff4a68f5bd2
  api_container="$(docker run --detach --rm --network "$network" --network-alias api \
    --env PGRST_DB_URI=postgres://jadis_api@database/postgres \
    --env PGRST_DB_SCHEMAS=public --env PGRST_DB_ANON_ROLE=anon \
    --env PGRST_JWT_SECRET "$api_image")"
  probe_image=python:3.12-slim@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b
  if ! docker run --rm --interactive --network "$network" --env PGRST_JWT_SECRET \
      "$probe_image" python - < scripts/check-beta-api.py; then
    docker logs "$api_container" >&2
    exit 1
  fi
fi
