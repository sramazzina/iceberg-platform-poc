#!/usr/bin/env bash
# Checks the nessie service: readiness, default branch, JDBC version store tables,
# and the warehouse that the Iceberg REST endpoint gives to clients.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
set -a; source .env; set +a

# curl runs inside the nessie container, so the test does not depend on the published ports.
nessie_get() { docker compose exec -T nessie curl -fsS "$1" 2>&1 || echo "request failed: $1"; }

echo "nessie"
ready=$(nessie_get http://127.0.0.1:9000/q/health/ready | jq -r .status 2>&1 || true)
assert_eq "$ready" "UP" "readiness check is UP"

branch=$(nessie_get http://127.0.0.1:19120/api/v2/trees/main | jq -r '.reference.type + ":" + .reference.name' 2>&1 || true)
assert_eq "$branch" "BRANCH:main" "default branch main exists"

tables=$(docker compose exec -T postgres psql -U postgres -d nessie -tAc \
  "SELECT string_agg(tablename || ':' || tableowner, ',' ORDER BY tablename) FROM pg_tables WHERE schemaname = 'public'" 2>&1 || true)
assert_eq "$tables" "objs2:nessie,refs2:nessie" "JDBC2 version store tables owned by nessie"

config=$(nessie_get http://127.0.0.1:19120/iceberg/v1/config | jq -r '.defaults.prefix + " " + .defaults.warehouse' 2>&1 || true)
assert_eq "$config" "main s3://$S3_BUCKET/nessie" "Iceberg REST prefix main and warehouse on nessie/"

refs=$(docker compose exec -T spark nessie -q --stdout -c "LIST REFERENCES" 2>&1 || echo "nessie CLI failed")
assert_contains "$refs" "BRANCH main @" "the Nessie CLI in the spark container lists the branch main"

finish
