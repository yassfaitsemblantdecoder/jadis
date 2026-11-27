#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
image=postgres:16@sha256:ce81150802644ddfac1db4da9e63be6f2a3818aa6ee98a7a28838aeea65dc37a
container=
api_container=
auth_container=
mail_container=
network=
cleanup() {
  local service
  for service in "$api_container" "$auth_container" "$mail_container" "$container"; do
    if [[ -n "$service" ]] && docker inspect "$service" >/dev/null 2>&1; then
      docker rm -f "$service" >/dev/null || printf 'Cleanup failed for %s\n' "$service" >&2
    fi
  done
  if [[ -n "$network" ]]; then
    docker network rm "$network" >/dev/null || printf 'Cleanup failed for %s\n' "$network" >&2
  fi
}
trap cleanup EXIT

mode="${1:-}"
database_network=(--network none)
if [[ "$mode" == --rest || "$mode" == --auth ]]; then
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

apply_migrations() {
  for migration in supabase/migrations/*.sql; do
    printf 'Applying %s to %s\n' "$migration" "$1"
    psql -d "$1" < "$migration"
  done
}

psql < supabase/tests/bootstrap.sql
psql < supabase/tests/auth-claims.sql
apply_migrations postgres
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

start_api() {
  local api_image=postgrest/postgrest:v12.2.12@sha256:5f4ce744539bbba786b4e24dbbd95bdb2a956dcf568c5374995a0ff4a68f5bd2
  docker run --detach --rm --network "$network" --network-alias api \
    --env "PGRST_DB_URI=postgres://jadis_api@database/$1" \
    --env PGRST_DB_SCHEMAS=public --env PGRST_DB_ANON_ROLE=anon \
    --env PGRST_JWT_SECRET "$api_image"
}

run_probe() {
  local probe_image=python:3.12-slim@sha256:191083cdf6c7bda8c76158983163ead5d5cf7b77cf3033e805bb0f5296f51b4b
  docker run --rm --interactive --network "$network" --env PGRST_JWT_SECRET \
    "$probe_image" python - < "$1"
}

if [[ "$mode" == --rest || "$mode" == --auth ]]; then
  psql < supabase/tests/api-fixtures.sql
  export PGRST_JWT_SECRET
  PGRST_JWT_SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
  api_container="$(start_api postgres)"
  if ! run_probe scripts/check-beta-api.py; then
    docker logs "$api_container" >&2
    exit 1
  fi
fi

if [[ "$mode" == --auth ]]; then
  docker stop "$api_container" >/dev/null
  api_container=
  docker exec "$container" createdb -U postgres jadis_auth
  psql -d jadis_auth -c 'create schema auth; alter database jadis_auth set search_path to auth, public;'
  export GOTRUE_JWT_SECRET="$PGRST_JWT_SECRET"
  mail_image=axllent/mailpit:v1.27.8@sha256:6abc8e633df15eaf785cfcf38bae48e66f64beecdc03121e249d0f9ec15f0707
  auth_image=supabase/gotrue:v2.177.0@sha256:6a916b47af0386b7e0152ca84f3d45d050bf056e449a75a5460b48742fd67822
  mail_container="$(docker run --detach --rm --network "$network" --network-alias mail "$mail_image")"
  auth_container="$(docker run --detach --network "$network" --network-alias auth \
    --env API_EXTERNAL_URL=http://auth:9999 \
    --env GOTRUE_API_HOST=0.0.0.0 --env GOTRUE_API_PORT=9999 \
    --env GOTRUE_SITE_URL=http://auth:9999 --env GOTRUE_DB_DRIVER=postgres \
    --env GOTRUE_DB_NAMESPACE=auth \
    --env 'GOTRUE_DB_DATABASE_URL=postgres://postgres@database/jadis_auth?sslmode=disable' \
    --env GOTRUE_JWT_SECRET --env GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated \
    --env GOTRUE_EXTERNAL_EMAIL_ENABLED=true --env GOTRUE_MAILER_AUTOCONFIRM=false \
    --env GOTRUE_RATE_LIMIT_EMAIL_SENT=20 --env GOTRUE_SMTP_MAX_FREQUENCY=1s \
    --env GOTRUE_SMTP_HOST=mail --env GOTRUE_SMTP_PORT=1025 \
    --env GOTRUE_SMTP_ADMIN_EMAIL=jadis@example.invalid --env GOTRUE_MAILER_URLPATHS_CONFIRMATION=/verify \
    --env GOTRUE_MAILER_URLPATHS_RECOVERY=/verify \
    "$auth_image")"

  ready=false
  for ((attempt = 0; attempt < 30; attempt++)); do
    if docker exec "$auth_container" wget -Y off -q -O /dev/null 2>/dev/null http://127.0.0.1:9999/health; then
      ready=true
      break
    fi
    sleep 1
  done
  if [[ "$ready" != true ]]; then
    docker logs "$auth_container" >&2
    exit 1
  fi
  psql -d jadis_auth < supabase/tests/auth-claims.sql
  apply_migrations jadis_auth
  psql -d jadis_auth <<'SQL'
insert into jadis_private.invite_codes (code_hash, expires_at)
values (encode(sha256(convert_to('JADIS-TEST-INVITE', 'UTF8')), 'hex'), now() + interval '1 hour');
SQL
  api_container="$(start_api jadis_auth)"
  if ! run_probe scripts/check-beta-auth.py; then
    docker logs "$auth_container" >&2
    docker logs "$api_container" >&2
    exit 1
  fi
fi
