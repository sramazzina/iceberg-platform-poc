#!/usr/bin/env bash
# Catalog acceptance test (spec section 6). Usage: tests/catalog-smoke.sh CATALOG
# Creates a table in CATALOG, writes two rows and reads them, checks that the files
# are under the S3 prefix of the catalog, restarts the stack, and reads the rows again.
# The table gets a unique name and is removed at the end, files included.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
if [[ -v COMPOSE_PROFILES ]]; then keep=$COMPOSE_PROFILES; fi
set -a; source .env; set +a
if [[ -v keep ]]; then COMPOSE_PROFILES=$keep; fi

catalog=${1:-}
ts=$(date +%s)
# Per-catalog policy.
# own_files=1: the VM role deletes the table files after the drop (Nessie never deletes files).
# own_files=0: DROP TABLE ... PURGE deletes the files with the credentials that the catalog
# vends; the VM role cannot write under polaris/.
case $catalog in
  nessie) prefix=nessie; drop_sql="DROP TABLE IF EXISTS %s"; own_files=1 ;;
  polaris) prefix=polaris; drop_sql="DROP TABLE IF EXISTS %s PURGE"; own_files=0 ;;
  *) echo "unknown catalog '$catalog'; usage: tests/catalog-smoke.sh nessie|polaris" >&2; exit 2 ;;
esac

table="$catalog.smoke.t_$ts"
root=""
created=0

# sql STATEMENTS: runs spark-sql in the spark container. Prints the result rows; on
# failure prints the end of the Spark log and "spark-sql failed".
sql() {
  docker compose exec -T spark bash -c \
    'err=$(mktemp); spark-sql -S -e "$1" 2>"$err" || { grep -m5 -E "Error|Exception" "$err"; tail -n 5 "$err"; echo "spark-sql failed"; }; rm -f "$err"' \
    _ "$1"
}

rows() { sql "SELECT concat('row=', id, ':', name) FROM $table ORDER BY id" | grep '^row=' || true; }

cleanup() {
  set +e
  ((created)) || return 0
  local out
  out=$(sql "$(printf "$drop_sql" "$table")" 2>&1)
  if [[ $out == *"spark-sql failed"* || -z $(docker compose ps -q --status running spark) ]]; then
    echo "  warn - could not drop $table; S3 files kept"
    return 0
  fi
  if ((!own_files)) && [[ -n $root ]]; then
    left=$(docker compose exec -T spark aws s3 ls --recursive "$root/" 2>/dev/null || true)
    if [[ -n $left ]]; then
      echo "  FAIL - files left under $root/ after the purge:"
      echo "$left"
      exit 1
    fi
  elif ((own_files)) && [[ -n $root ]]; then
    docker compose exec -T spark aws s3 rm --recursive --quiet "$root/" >/dev/null 2>&1 \
      || echo "  warn - could not delete $root/"
  elif ((own_files)); then
    echo "  warn - table root unknown; S3 files of $table kept"
  fi
}
trap cleanup EXIT

echo "catalog $catalog"
# The namespace smoke stays (empty, reused); Nessie keeps the dropped table in the history of main.
out=$(sql "CREATE NAMESPACE IF NOT EXISTS $catalog.smoke;
CREATE TABLE $table (id INT, name STRING) USING iceberg;
INSERT INTO $table VALUES (1, 'a'), (2, 'b');")
created=1
assert_not_contains "$out" "spark-sql failed" "create a namespace and a table, insert two rows"
assert_eq "$(rows)" $'row=1:a\nrow=2:b' "read the two rows"

path=$(sql "SELECT file_path FROM $table.files" | grep '^s3://' | head -n 1 || true)
want="s3://$S3_BUCKET/$prefix/"
assert_eq "${path:0:${#want}}" "$want" "data file under the $prefix/ prefix"
if [[ $path == */data/* ]]; then root=${path%/data/*}; fi
[[ $root == "$want"*"/t_${ts}"* ]] || { fail "table root '$root' not under $want with t_$ts"; root=""; }

if [[ -n $root ]]; then
  listing=$(docker compose exec -T spark aws s3 ls --recursive "$root/" 2>&1 || true)
else
  listing=""
  fail "table root not found in data file path '$path'"
fi
assert_contains "$listing" ".parquet" "aws s3 ls shows the data file"
assert_contains "$listing" ".metadata.json" "aws s3 ls shows the table metadata"

if [[ $catalog == nessie ]]; then
  if logs=$(docker compose logs --no-color nessie 2>&1); then
    assert_not_contains "$logs" "s3sign" "Spark uses its own S3 credentials (no request signing by Nessie)"
  else
    fail "read the nessie logs"
  fi
fi

echo "restart"
if docker compose stop >/dev/null 2>&1 && docker compose up -d --wait >/dev/null 2>&1; then
  pass "stack restart (stop and up)"
else
  fail "stack restart (stop and up)"
fi
assert_eq "$(rows)" $'row=1:a\nrow=2:b' "the table and its rows survive the restart"

finish
