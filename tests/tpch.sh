#!/usr/bin/env bash
# Checks the EL steps (spec 2026-10-30-dbt-elt, sections 6.3 and 6.4) on one catalog:
# make tpch-gen, make tpch-load (with and without UNTIL), the error messages, and
# make tpch-clean. The test drops the namespaces tpch_raw, tpch_staging and tpch_marts of
# CATALOG, with any data in them. Usage: tests/tpch.sh CATALOG (polaris, nessie or rest).
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
source "$ROOT/tests/lib/spark-sql.sh"
cd "$ROOT"
if [[ -v COMPOSE_PROFILES ]]; then keep=$COMPOSE_PROFILES; fi
set -a; source .env; set +a
if [[ -v keep ]]; then COMPOSE_PROFILES=$keep; fi

catalog=${1:-}
case $catalog in
  polaris | nessie | rest) ;;
  *) echo "usage: tests/tpch.sh polaris|nessie|rest" >&2; exit 2 ;;
esac
sf=0.01
dir=landing/tpch/sf$sf
trap 'make -s tpch-clean CATALOG="$catalog" >/dev/null 2>&1 || echo "  warn - make tpch-clean CATALOG=$catalog failed"' EXIT

# count TABLE: the row count of CATALOG.tpch_raw.TABLE.
count() { spark_sql "SELECT concat('n=', count(*)) FROM $catalog.tpch_raw.$1" | sed -n 's/^n=//p'; }
# parquet_count TABLE: the row count of the generated Parquet file of TABLE.
parquet_count() {
  docker compose exec -T spark python3 -c 'import duckdb, sys; print(duckdb.sql("SELECT count(*) FROM read_parquet(?)", params=[sys.argv[1]]).fetchone()[0])' \
    "/workspace/$dir/$1.parquet" 2>&1
}
# left: the number of objects under the S3 prefix of the catalog in a tpch_ namespace.
left() {
  local out rc=0
  out=$(docker compose exec -T spark bash -c "aws s3 ls --recursive s3://\$S3_BUCKET/$catalog/" 2>&1) || rc=$?
  if (( rc > 1 )); then echo "$out"; echo "left: aws s3 ls failed"; return; fi
  grep -c '/tpch_' <<<"$out" || true
}
# lineitem_count: the lineitem rows of the orders with o_orderdate <= DATE '1996-12-31'.
lineitem_count() {
  docker compose exec -T spark python3 -c 'import duckdb, sys; d = sys.argv[1]; print(duckdb.sql(f"SELECT count(*) FROM read_parquet(\x27{d}/lineitem.parquet\x27) WHERE l_orderkey IN (SELECT o_orderkey FROM read_parquet(\x27{d}/orders.parquet\x27) WHERE o_orderdate <= DATE \x271996-12-31\x27)").fetchone()[0])' \
    "/workspace/$dir" 2>&1
}

echo "tpch $catalog"
out=$(make -s elt-require CATALOG=no-such 2>&1 || true)
assert_contains "$out" "set CATALOG=polaris|nessie|rest" "an unknown catalog gives a clear message"
out=$(COMPOSE_PROFILES= make -s tpch-load CATALOG="$catalog" SF=$sf 2>&1 || true)
assert_contains "$out" "catalog $catalog is off" "a catalog that is off gives a clear message"
out=$(make -s tpch-load CATALOG="$catalog" SF=0.123 2>&1 || true)
assert_contains "$out" "run make tpch-gen SF=0.123 first" "missing Parquet files give a clear message"

out=$(make -s tpch-gen SF=$sf 2>&1 || echo "tpch-gen failed")
assert_not_contains "$out" "tpch-gen failed" "make tpch-gen SF=$sf"
for t in region nation customer supplier part partsupp orders lineitem; do
  [[ -f $dir/$t.parquet ]] || fail "missing $dir/$t.parquet"
done
assert_contains "$(make -s tpch-gen SF=$sf 2>&1)" "nothing to do" "a second make tpch-gen does nothing"

out=$(make -s tpch-load CATALOG="$catalog" SF=$sf UNTIL=1996-12-31 2>&1 || echo "tpch-load failed")
assert_not_contains "$out" "tpch-load failed" "make tpch-load UNTIL=1996-12-31"
assert_contains "$out" "tpch-load: $catalog.tpch_raw.lineitem:" "tpch-load reports the last table"
assert_eq "$(spark_sql "SELECT concat('d=', max(o_orderdate) <= DATE'1996-12-31') FROM $catalog.tpch_raw.orders" | sed -n 's/^d=//p')" \
  "true" "orders stop at UNTIL"
assert_eq "$(spark_sql "SELECT concat('n=', count(*)) FROM $catalog.tpch_raw.lineitem l LEFT ANTI JOIN $catalog.tpch_raw.orders o ON l.l_orderkey = o.o_orderkey" | sed -n 's/^n=//p')" \
  "0" "lineitem keeps only the rows of the loaded orders"
assert_eq "$(count lineitem)" "$(lineitem_count)" "lineitem has the rows of the orders up to UNTIL"
assert_eq "$(count customer)" "$(parquet_count customer)" "customer loaded in full with UNTIL"
partial=$(count orders)

out=$(make -s tpch-load CATALOG="$catalog" SF=$sf 2>&1 || echo "tpch-load failed")
assert_not_contains "$out" "tpch-load failed" "make tpch-load (full)"
for t in region nation customer supplier part partsupp orders lineitem; do
  assert_eq "$(count "$t")" "$(parquet_count "$t")" "tpch_raw.$t has the rows of the Parquet file"
done
(( partial < $(count orders) )) && pass "the full load has more orders than the UNTIL load" \
  || fail "the full load has more orders than the UNTIL load"

(( $(left) > 0 )) && pass "the S3 probe sees the tpch_raw files" || fail "the S3 probe sees the tpch_raw files"

out=$(make -s tpch-clean CATALOG="$catalog" 2>&1 || echo "tpch-clean failed")
assert_not_contains "$out" "tpch-clean failed" "make tpch-clean"
assert_not_contains "$out" "tpch-clean: FAIL" "make tpch-clean leaves no file"
assert_not_contains "$(spark_sql "SHOW NAMESPACES IN $catalog")" "tpch_raw" "namespace tpch_raw dropped"
assert_eq "$(left)" "0" "no object left under $catalog/ in a tpch_ namespace"

finish
