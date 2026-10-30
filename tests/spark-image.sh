#!/usr/bin/env bash
# Checks the content of the spark image: Iceberg jars, AWS CLI, Python packages,
# Spark SQL with the Iceberg extensions.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
set -a; source .env; set +a

run() { docker compose run --rm --no-deps -T spark "$@" 2>&1 || echo "command failed (exit $?)"; }

echo "spark image"
jars=$(run bash -c 'ls "$SPARK_HOME/jars"')
assert_contains "$jars" "$ICEBERG_SPARK_RUNTIME_ARTIFACT-$ICEBERG_VERSION.jar" "Iceberg Spark runtime"
assert_contains "$jars" "iceberg-aws-bundle-$ICEBERG_VERSION.jar" "Iceberg AWS bundle"
assert_contains "$(run aws --version)" "aws-cli/$AWSCLI_VERSION" "AWS CLI pinned version"
py=$(run python3 -c 'import pyspark, pyiceberg, pandas, jupyterlab, requests; print(pyspark.__version__, pyiceberg.__version__)')
assert_contains "$py" "4.1.3 0.12.0" "PySpark and PyIceberg import"
tools=$(run python3 -c 'import dbt.version, duckdb, pyhive, thrift; from importlib.metadata import version; print("dbt-core", version("dbt-core"), "dbt-spark", version("dbt-spark"), "duckdb", duckdb.__version__, "thrift", version("thrift"))')
assert_contains "$tools" "dbt-core 1.12.6 dbt-spark 1.11.0 duckdb 1.5.6 thrift 0.22.0" "dbt, dbt-spark, DuckDB and thrift pinned versions"
assert_contains "$(run dbt --version)" "spark: 1.11.0" "dbt finds the spark adapter"
tpch=$(run python3 -c 'import duckdb; c = duckdb.connect(); c.execute("SET autoinstall_known_extensions = false"); c.execute("CALL dbgen(sf = 0.001)"); print("region=%d" % c.sql("SELECT count(*) FROM region").fetchone()[0])')
assert_contains "$tpch" "region=5" "DuckDB tpch works without a download"
assert_contains "$jars" "spark-hive-thriftserver_2.13-4.1.3.jar" "Spark Thrift Server jar"
assert_contains "$(run bash -c 'ls "$SPARK_HOME/bin"')" "beeline" "beeline (Hive JDBC client)"
sql=$(run bash -c "spark-sql -S -e \"SELECT 'answer=' || (41 + 1)\" 2>/dev/null")
assert_contains "$sql" "answer=42" "spark-sql runs"
ext=$(run bash -c "spark-sql -S \
  --conf spark.sql.catalog.t=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.t.type=hadoop \
  --conf spark.sql.catalog.t.warehouse=\$(mktemp -d) \
  -e \"CREATE TABLE t.db.x (id INT) USING iceberg; ALTER TABLE t.db.x WRITE ORDERED BY id; SELECT 'extensions=ok';\"")
assert_contains "$ext" "extensions=ok" "Iceberg extensions configured"
assert_not_contains "$ext" "configure session extensions" "no extension load error"
assert_not_contains "$jars" "nessie-cli" "Nessie CLI jar not on the Spark classpath"
assert_eq "$(run nessie --version | tail -n1)" "$NESSIE_CLI_VERSION" "Nessie CLI pinned version"
assert_eq "$NESSIE_CLI_VERSION" "${NESSIE_IMAGE##*:}" "Nessie CLI version equals the Nessie server version"

uid=$(run id -u)
assert_eq "$(tail -n1 <<<"$uid")" "$LAB_UID" "runs as LAB_UID"

finish
