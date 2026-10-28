#!/usr/bin/env bash
# Catalog acceptance test (spec section 6). Usage: tests/catalog-smoke.sh CATALOG
# Creates a table in CATALOG, writes two rows and reads them, checks that the files
# are under the S3 prefix of the catalog, restarts the stack, and reads the rows again.
# The table gets a unique name and is removed at the end, files included.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
set -a; source .env; set +a

catalog=${1:-}
case $catalog in
  nessie) prefix=nessie ;;
  *) echo "usage: tests/catalog-smoke.sh nessie" >&2; exit 2 ;;
esac

table="$catalog.smoke.t_$(date +%s)"
root=""

# sql STATEMENTS: runs spark-sql in the spark container. Prints the result rows; on
# failure prints the end of the Spark log and "spark-sql failed".
sql() {
  docker compose exec -T spark bash -c \
    'spark-sql -S -e "$1" 2>/tmp/catalog-smoke.err || { tail -n 20 /tmp/catalog-smoke.err; echo "spark-sql failed"; }' \
    _ "$1"
}

rows() { sql "SELECT concat('row=', id, ':', name) FROM $table ORDER BY id" | grep '^row=' || true; }

cleanup() {
  sql "DROP TABLE IF EXISTS $table" >/dev/null
  if [[ -n $root ]]; then
    docker compose exec -T spark aws s3 rm --recursive --quiet "$root/" >/dev/null 2>&1 \
      || echo "  warn - could not delete $root/"
  fi
}
trap cleanup EXIT

echo "catalog $catalog"
out=$(sql "CREATE NAMESPACE IF NOT EXISTS $catalog.smoke;
CREATE TABLE $table (id INT, name STRING) USING iceberg;
INSERT INTO $table VALUES (1, 'a'), (2, 'b');")
assert_not_contains "$out" "spark-sql failed" "create a namespace and a table, insert two rows"
assert_eq "$(rows)" $'row=1:a\nrow=2:b' "read the two rows"

path=$(sql "SELECT file_path FROM $table.files" | grep '^s3://' | head -n 1 || true)
want="s3://$S3_BUCKET/$prefix/"
assert_eq "${path:0:${#want}}" "$want" "data file under the $prefix/ prefix"
if [[ $path == */data/* ]]; then root=${path%/data/*}; fi

listing=$(docker compose exec -T spark aws s3 ls --recursive "${root:-$want}/" 2>&1 || true)
assert_contains "$listing" ".parquet" "aws s3 ls shows the data file"
assert_contains "$listing" ".metadata.json" "aws s3 ls shows the table metadata"

if [[ $catalog == nessie ]]; then
  assert_not_contains "$(docker compose logs nessie 2>&1)" "s3sign" \
    "Spark uses its own S3 credentials (no request signing by Nessie)"
fi

echo "restart"
if docker compose restart >/dev/null 2>&1 && docker compose up -d --wait >/dev/null 2>&1; then
  pass "docker compose restart"
else
  fail "docker compose restart"
fi
assert_eq "$(rows)" $'row=1:a\nrow=2:b' "the table and its rows survive the restart"

finish
