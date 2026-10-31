"""Loads the TPC-H Parquet files into CATALOG.tpch_raw (spec 2026-10-30-dbt-elt,
section 6.4). Usage: spark-submit tpch_load.py CATALOG SF [UNTIL]
With UNTIL (YYYY-MM-DD), orders keeps the rows with o_orderdate <= UNTIL and lineitem keeps
the rows of those orders. Every table is replaced (CREATE OR REPLACE)."""
import datetime
import pathlib
import sys

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, lit

from tpch_gen import TABLES

CATALOGS = ("polaris", "nessie", "rest")


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit("usage: tpch_load.py CATALOG SF [UNTIL]")
    catalog, sf = sys.argv[1], sys.argv[2]
    until = sys.argv[3] if len(sys.argv) == 4 and sys.argv[3] else None
    if catalog not in CATALOGS:
        sys.exit(f"tpch-load: CATALOG must be one of {', '.join(CATALOGS)} (got '{catalog}')")
    until_date = None
    if until:
        try:
            until_date = datetime.date.fromisoformat(until)
        except ValueError:
            sys.exit(f"tpch-load: UNTIL must be a date YYYY-MM-DD (got '{until}')")
    src = pathlib.Path("/workspace/landing/tpch") / f"sf{sf}"
    if not all((src / f"{t}.parquet").exists() for t in TABLES):
        sys.exit(f"tpch-load: no complete data in landing/tpch/sf{sf}: run make tpch-gen SF={sf} first")

    spark = SparkSession.builder.appName("tpch-load").getOrCreate()
    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {catalog}.tpch_raw")
    orders = spark.read.parquet(str(src / "orders.parquet"))
    if until:
        orders = orders.where(col("o_orderdate") <= lit(until_date))
    for t in TABLES:
        if t == "orders":
            df = orders
        else:
            df = spark.read.parquet(str(src / f"{t}.parquet"))
        if t == "lineitem" and until:
            df = df.join(orders.select("o_orderkey"), df.l_orderkey == orders.o_orderkey, "left_semi")
        name = f"{catalog}.tpch_raw.{t}"
        df.writeTo(name).using("iceberg").createOrReplace()
        print(f"tpch-load: {name}: {spark.table(name).count()} rows")
    spark.stop()


if __name__ == "__main__":
    main()
