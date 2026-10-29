#!/usr/bin/env bash
# Checks the Spark configuration that the entrypoint renders for a catalog selection.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

# conf CATALOGS: the rendered spark-defaults.conf for LAB_CATALOGS=CATALOGS.
conf() {
  docker compose run --rm --no-deps -T -e LAB_CATALOGS="$1" spark \
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

nessie=$(conf nessie)
assert_contains "$nessie" "spark.sql.catalog.nessie.uri    http://nessie:19120/iceberg/main" "nessie block with nessie"
assert_contains "$nessie" "IcebergSparkSessionExtensions" "common part with nessie"

unknown=$(conf baseline)
assert_not_contains "$unknown" "command failed" "a profile without a template is skipped"
assert_not_contains "$unknown" "no Spark catalog" "the warning is not in the rendered file"
assert_contains "$(conf_err baseline)" "no Spark catalog for profile 'baseline'" "a profile without a template gives a warning on stderr"

finish
