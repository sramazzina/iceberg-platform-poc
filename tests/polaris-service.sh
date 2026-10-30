#!/usr/bin/env bash
# Checks the polaris services: readiness, catalog lab_catalog, roles and grants,
# the spark_user credentials file, and that Spark uses spark_user, never root.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
# Keep the COMPOSE_PROFILES of the caller: .env would overwrite it.
if [[ -v COMPOSE_PROFILES ]]; then keep=$COMPOSE_PROFILES; fi
set -a; source .env; set +a
if [[ -v keep ]]; then COMPOSE_PROFILES=$keep; fi

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

roles=$(api /principals/spark_user/principal-roles | jq -r '[.roles[].name] | join(",")' 2>&1 || true)
assert_eq "$roles" "spark_role" "principal spark_user has spark_role"

assert_eq "$(docker compose logs polaris-bootstrap 2>&1 | grep -cF -- "$POLARIS_ROOT_CLIENT_SECRET" || true)" "0" "the bootstrap log does not show the root secret"

# The variant keeps its own credentials file (spec section 6.4).
creds=secrets/spark_user.env
if docker compose config --services | grep -qx rustfs; then creds=secrets/rustfs/spark_user.env; fi
mode=$(stat -c %a "$creds" 2>&1 || true)
assert_eq "$mode" "600" "$creds exists, mode 600"

client=$(docker compose exec -T spark sh -c \
  "sed -n 's/^spark.sql.catalog.polaris.credential *\([^:]*\):.*/\1/p' /opt/spark/conf/spark-defaults.conf" 2>&1 || true)
spark_id=$(sed -n 's/^POLARIS_SPARK_CLIENT_ID=//p' "$creds" 2>/dev/null || true)
assert_not_contains "$client" "$POLARIS_ROOT_CLIENT_ID" "Spark does not use the root credentials"
assert_eq "$client" "$spark_id" "Spark uses the spark_user client id"
assert_eq "$(grep -c . <<<"$client")" "1" "Spark has one polaris credential"

if [[ $mode == 600 ]]; then
  rerun=$(docker compose run --rm --no-deps polaris-setup 2>&1 || echo "polaris-setup failed")
  assert_contains "$rerun" "credentials file kept" "a second polaris-setup run keeps the credentials"
  assert_not_contains "$rerun" "polaris-setup failed" "a second polaris-setup run succeeds"
fi

finish
