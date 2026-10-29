#!/usr/bin/env bash
# Checks the polaris services: readiness, catalog lab_catalog, roles and grants,
# the spark_user credentials file, and that Spark uses spark_user, never root.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
set -a; source .env; set +a

# curl runs inside the polaris container, so the test does not depend on the published ports.
# api PATH: GET on the management API as root. The root credentials stay in the container env.
api() {
  docker compose exec -T -e POLARIS_ROOT_CLIENT_ID -e POLARIS_ROOT_CLIENT_SECRET polaris bash -c '
    token=$(curl -fsS -X POST http://127.0.0.1:8181/api/catalog/v1/oauth/tokens \
      --user "$POLARIS_ROOT_CLIENT_ID:$POLARIS_ROOT_CLIENT_SECRET" \
      -d grant_type=client_credentials -d scope=PRINCIPAL_ROLE:ALL \
      | sed -n "s/.*\"access_token\":\"\([^\"]*\)\".*/\1/p")
    curl -fsS -H "Authorization: Bearer $token" "http://127.0.0.1:8181/api/management/v1$1"' _ "$1" \
    2>&1 || echo "request failed: $1"
}

echo "polaris"
ready=$(docker compose exec -T polaris curl -fsS http://127.0.0.1:8182/q/health/ready 2>&1 | jq -r .status 2>&1 || true)
assert_eq "$ready" "UP" "readiness check is UP"

catalog=$(api /catalogs/lab_catalog | jq -r '.storageConfigInfo.storageType + " " + .properties["default-base-location"]' 2>&1 || true)
assert_eq "$catalog" "S3 s3://$S3_BUCKET/polaris/" "catalog lab_catalog on S3 with base location polaris/"

grants=$(api /catalogs/lab_catalog/catalog-roles/lab_admin/grants | jq -r '[.grants[].privilege] | join(",")' 2>&1 || true)
assert_contains "$grants" "CATALOG_MANAGE_CONTENT" "catalog role lab_admin can manage content"

roles=$(api /principal-roles/spark_role/catalog-roles/lab_catalog | jq -r '[.roles[].name] | join(",")' 2>&1 || true)
assert_eq "$roles" "lab_admin" "principal role spark_role has lab_admin"

assert_eq "$(stat -c %a secrets/spark_user.env 2>&1 || true)" "600" "secrets/spark_user.env exists, mode 600"

client=$(docker compose exec -T spark sh -c \
  "sed -n 's/^spark.sql.catalog.polaris.credential *\([^:]*\):.*/\1/p' /opt/spark/conf/spark-defaults.conf" 2>&1 || true)
assert_not_contains "$client" "$POLARIS_ROOT_CLIENT_ID" "Spark does not use the root credentials"
assert_eq "$(grep -c . <<<"$client")" "1" "Spark has one polaris credential"

rerun=$(docker compose run --rm --no-deps polaris-setup 2>&1 || echo "polaris-setup failed")
assert_contains "$rerun" "credentials file kept" "a second polaris-setup run keeps the credentials"
assert_not_contains "$rerun" "polaris-setup failed" "a second polaris-setup run succeeds"

finish
