#!/usr/bin/env bash
# Checks the Spark configuration that the entrypoint renders for a catalog selection.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

# conf CATALOGS: the rendered spark-defaults.conf for LAB_CATALOGS=CATALOGS, on AWS (no endpoint).
conf() {
  docker compose run --rm --no-deps -T -e LAB_CATALOGS="$1" -e S3_ENDPOINT= spark \
    cat /opt/spark/conf/spark-defaults.conf 2>/dev/null || echo "command failed"
}

# conf_endpoint CATALOGS: the same, with an S3-compatible endpoint.
conf_endpoint() {
  docker compose run --rm --no-deps -T -e LAB_CATALOGS="$1" \
    -e S3_ENDPOINT=http://rustfs:9000 -e S3_PATH_STYLE_ACCESS=true spark \
    cat /opt/spark/conf/spark-defaults.conf 2>/dev/null || echo "command failed"
}

# conf_err CATALOGS: what the entrypoint prints on stderr for LAB_CATALOGS=CATALOGS.
conf_err() {
  docker compose run --rm --no-deps -T -e LAB_CATALOGS="$1" spark true 2>&1 >/dev/null || echo "command failed"
}

echo "spark configuration"
none=$(conf "")
assert_contains "$none" "IcebergSparkSessionExtensions" "common part with no catalog"
assert_not_contains "$none" "spark.sql.catalog.nessie" "no nessie block with no catalog"
assert_not_contains "$none" "spark.sql.catalog.rest" "no rest block with no catalog"

nessie=$(conf nessie)
assert_contains "$nessie" "spark.sql.catalog.nessie.uri    http://nessie:19120/iceberg/main" "nessie block with nessie"
assert_contains "$nessie" "IcebergSparkSessionExtensions" "common part with nessie"

unknown=$(conf no-such-catalog)
assert_not_contains "$unknown" "command failed" "a profile without a template is skipped"
assert_not_contains "$unknown" "no Spark catalog" "the warning is not in the rendered file"
assert_contains "$(conf_err no-such-catalog)" "no Spark catalog for profile 'no-such-catalog'" "a profile without a template gives a warning on stderr"

polaris=$(conf polaris)
assert_contains "$polaris" "spark.sql.catalog.polaris.uri                                 http://polaris:8181/api/catalog" "polaris block with polaris"
assert_not_contains "$polaris" '${POLARIS_SPARK_CLIENT' "polaris credentials rendered"

rest=$(conf baseline)
assert_contains "$rest" "spark.sql.catalog.rest.uri    http://rest-fixture:8181" "rest block with baseline"
assert_not_contains "$nessie" "spark.sql.catalog.rest" "no rest block with nessie only"
assert_not_contains "$rest" "spark.sql.catalog.rest.s3.endpoint" "no S3 endpoint for rest on AWS"
rest_endpoint=$(conf_endpoint baseline)
assert_contains "$rest_endpoint" "spark.sql.catalog.rest.s3.endpoint            http://rustfs:9000" "S3 endpoint for rest with S3_ENDPOINT"
assert_contains "$rest_endpoint" "spark.sql.catalog.rest.s3.path-style-access   true" "path-style access for rest with S3_ENDPOINT"
assert_not_contains "$(conf_endpoint nessie)" ".s3.endpoint" "no S3 endpoint template for nessie (Nessie gives it to clients)"

finish
