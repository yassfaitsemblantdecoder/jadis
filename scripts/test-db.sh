#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
image=postgres:16@sha256:ce81150802644ddfac1db4da9e63be6f2a3818aa6ee98a7a28838aeea65dc37a
container="$(docker run --detach --rm --network none \
  --tmpfs /var/lib/postgresql/data \
  --env POSTGRES_HOST_AUTH_METHOD=trust "$image")"
trap 'docker stop "$container" >/dev/null' EXIT

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

printf 'Restoring and retesting the migrated schema
'
docker exec "$container" createdb -U postgres foundation_restore
docker exec "$container" pg_dump -U postgres --no-password postgres |
  psql --quiet -d foundation_restore
psql -d foundation_restore < supabase/tests/foundation.sql
