#!/usr/bin/env bash
# Checks that Postgres has the polaris and nessie databases, their owners,
# and the schema that Polaris expects.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

psql_super() { docker compose exec -T postgres psql -U postgres -tAc "$1"; }

echo "postgres"
dbs=$(psql_super "SELECT string_agg(datname || ':' || pg_get_userbyid(datdba), ',' ORDER BY datname) FROM pg_database WHERE datname IN ('polaris', 'nessie')")
assert_eq "$dbs" "nessie:nessie,polaris:polaris" "databases polaris and nessie with their own owners"
schema=$(docker compose exec -T postgres psql -U postgres -d polaris -tAc \
  "SELECT schema_owner FROM information_schema.schemata WHERE schema_name = 'polaris_schema'")
assert_eq "$schema" "polaris" "schema polaris_schema owned by polaris"
for user in polaris nessie; do
  # Inside the container: PGPASSWORD="$POLARIS_DB_PASSWORD" (or NESSIE_...).
  out=$(docker compose exec -T postgres sh -c \
    "PGPASSWORD=\"\$${user^^}_DB_PASSWORD\" psql -h 127.0.0.1 -U $user -d $user -tAc 'SELECT 1'")
  assert_eq "$out" "1" "user $user logs in with its password"
done

finish
