#!/usr/bin/env bash
# Checks that Postgres has the polaris and nessie databases, their owners,
# and the schema that Polaris expects.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

psql_super() { docker compose exec -T postgres psql -U postgres -d "${2:-postgres}" -tAc "$1"; }

echo "postgres"
dbs=$(psql_super "SELECT string_agg(datname || ':' || pg_get_userbyid(datdba), ',' ORDER BY datname) FROM pg_database WHERE datname IN ('polaris', 'nessie')" 2>&1 || true)
assert_eq "$dbs" "nessie:nessie,polaris:polaris" "databases polaris and nessie with their own owners"
schema=$(psql_super "SELECT schema_owner FROM information_schema.schemata WHERE schema_name = 'polaris_schema'" polaris 2>&1 || true)
assert_eq "$schema" "polaris" "schema polaris_schema owned by polaris"
# Log in over TCP through the service name: the scram-sha-256 rule applies.
# The loopback address is trusted by the image, so it would accept any password.
for user in polaris nessie; do
  # Inside the container: PGPASSWORD="$POLARIS_DB_PASSWORD" (or NESSIE_...).
  out=$(docker compose exec -T postgres sh -c \
    "PGPASSWORD=\"\$${user^^}_DB_PASSWORD\" psql -h postgres -U $user -d $user -tAc 'SELECT 1'" 2>&1 || true)
  assert_eq "$out" "1" "user $user logs in with its password"
  bad=$(docker compose exec -T postgres sh -c \
    "PGPASSWORD=wrong-password psql -h postgres -U $user -d $user -tAc 'SELECT 1'" 2>&1 || true)
  assert_contains "$bad" "password authentication failed" "user $user is rejected with a wrong password"
done

finish
