#!/usr/bin/env bash
# Checks the spark-thrift service (spec 2026-10-30-dbt-elt, section 7): a JDBC client
# (beeline) and the Python client of dbt (PyHive) run SQL, and each catalog that is on
# answers through the Thrift Server.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

# jdbc SQL: runs SQL with beeline (Hive JDBC driver) in the spark-thrift container.
# Prints the result rows without header; prints "beeline failed" on a non-zero exit.
# Beeline prefixes the first output line with its prompt ("0: jdbc:hive2://...> "): sed removes it.
jdbc() {
  docker compose exec -T spark-thrift beeline -u 'jdbc:hive2://127.0.0.1:10000/;auth=noSasl' -n spark \
    --silent=true --showHeader=false --outputformat=tsv2 -e "$1" 2>&1 | sed 's/^[0-9]*: jdbc:hive2:[^>]*> //' \
    || echo "beeline failed"
}

echo "spark-thrift"
assert_eq "$(jdbc 'SELECT 41 + 1' | grep -x 42 || true)" "42" "beeline (JDBC) runs SQL"
py=$(docker compose exec -T spark python3 -c '
from pyhive import hive
cur = hive.connect("spark-thrift", 10000, username="spark", auth="NOSASL").cursor()
cur.execute("SELECT 41 + 1")
print("answer=%s" % cur.fetchone()[0])' 2>&1 || echo "pyhive failed")
assert_contains "$py" "answer=42" "PyHive (client of dbt) runs SQL from the spark container"

services=$(docker compose config --services)
for entry in nessie:nessie polaris:polaris rest-fixture:rest; do
  service=${entry%%:*}
  catalog=${entry#*:}
  if grep -qx "$service" <<<"$services"; then
    out=$(jdbc "SHOW NAMESPACES IN $catalog")
    assert_not_contains "$out" "failed" "SHOW NAMESPACES IN $catalog through the Thrift Server"
    assert_not_contains "$out" "Error" "no error for $catalog"
  fi
done
assert_eq "$(docker compose port spark-thrift 10000 2>&1)" "127.0.0.1:10000" "port 10000 published on 127.0.0.1 only"

finish
