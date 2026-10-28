#!/usr/bin/env bash
# Checks the content of the spark image: Iceberg jars, AWS CLI, Python packages,
# Spark SQL with the Iceberg extensions.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
set -a; source .env; set +a

run() { docker compose run --rm --no-deps -T spark "$@" 2>&1; }

echo "spark image"
jars=$(run bash -c 'ls "$SPARK_HOME/jars"')
assert_contains "$jars" "$ICEBERG_SPARK_RUNTIME_ARTIFACT-$ICEBERG_VERSION.jar" "Iceberg Spark runtime"
assert_contains "$jars" "iceberg-aws-bundle-$ICEBERG_VERSION.jar" "Iceberg AWS bundle"
assert_contains "$(run aws --version)" "aws-cli/$AWSCLI_VERSION" "AWS CLI pinned version"
py=$(run python3 -c 'import pyspark, pyiceberg, pandas, jupyterlab, requests; print(pyspark.__version__, pyiceberg.__version__)')
assert_contains "$py" "4.1.3 0.12.0" "PySpark and PyIceberg import"
sql=$(run spark-sql -e "SELECT 41 + 1 AS answer")
assert_contains "$sql" "42" "spark-sql runs"
ext=$(run spark-sql -e "SET spark.sql.extensions")
assert_contains "$ext" "IcebergSparkSessionExtensions" "Iceberg extensions configured"
uid=$(run id -u)
assert_eq "$(tail -n1 <<<"$uid")" "$LAB_UID" "runs as LAB_UID"

finish
