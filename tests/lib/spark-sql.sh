# spark_sql STATEMENTS: runs spark-sql in the spark container. Prints the result rows; on
# failure prints the end of the Spark log and "spark-sql failed". Source this file; do not
# run it.
spark_sql() {
  docker compose exec -T spark bash -c \
    'err=$(mktemp); spark-sql -S -e "$1" 2>"$err" || { grep -m5 -E "Error|Exception" "$err"; tail -n 5 "$err"; echo "spark-sql failed"; }; rm -f "$err"' \
    _ "$1"
}
