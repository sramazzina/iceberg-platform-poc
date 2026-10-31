"""Drops the namespaces tpch_marts, tpch_staging and tpch_raw of CATALOG with their tables,
views and files (spec 2026-10-30-dbt-elt, section 6.6). Usage: spark-submit tpch_clean.py CATALOG
Drop policy per catalog (tests/catalog-smoke.sh): nessie never deletes files, so the files
are deleted with the AWS CLI; polaris deletes them with PURGE (the VM role can only list
under polaris/); rest deletes them with PURGE, the AWS CLI deletes what is left."""
import os
import subprocess
import sys

from pyspark.errors import AnalysisException
from pyspark.sql import SparkSession

NAMESPACES = ["tpch_marts", "tpch_staging", "tpch_raw"]
PURGE = {"nessie": False, "polaris": True, "rest": True}
OWN_FILES = {"nessie": True, "polaris": False, "rest": True}


def aws(*args):
    return subprocess.run(["aws", "s3", *args], capture_output=True, text=True)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in PURGE:
        sys.exit("usage: tpch_clean.py polaris|nessie|rest")
    catalog = sys.argv[1]
    root = f"s3://{os.environ['S3_BUCKET']}/{catalog}/"
    spark = SparkSession.builder.appName("tpch-clean").getOrCreate()
    present = {r[0] for r in spark.sql(f"SHOW NAMESPACES IN {catalog}").collect()}
    failed = False
    for ns in NAMESPACES:
        if ns not in present:
            continue
        try:
            views = {r.viewName for r in spark.sql(f"SHOW VIEWS IN {catalog}.{ns}").collect() if not r.isTemporary}
        except AnalysisException:
            views = set()  # The catalog has no Iceberg views (NOTES F7, S4).
        for v in sorted(views):
            spark.sql(f"DROP VIEW IF EXISTS {catalog}.{ns}.{v}")
            print(f"tpch-clean: dropped view {catalog}.{ns}.{v}")
        tables = [r.tableName for r in spark.sql(f"SHOW TABLES IN {catalog}.{ns}").collect()
                  if not r.isTemporary and r.tableName not in views]
        for t in sorted(tables):
            name = f"{catalog}.{ns}.{t}"
            rows = spark.sql(f"DESCRIBE TABLE EXTENDED {name}").where("col_name = 'Location'").collect()
            location = rows[0].data_type.rstrip("/") + "/" if rows else None
            prefix = f"{root}{ns}/"
            if not location or not location.startswith(prefix) or location == prefix:
                print(f"tpch-clean: FAIL - location of {name} not under {prefix}: {location}")
                failed = True
                continue
            spark.sql(f"DROP TABLE IF EXISTS {name}{' PURGE' if PURGE[catalog] else ''}")
            print(f"tpch-clean: dropped table {name}")
            if OWN_FILES[catalog]:
                rm = aws("rm", "--recursive", "--quiet", location)
                if rm.returncode != 0:
                    print(f"tpch-clean: FAIL - cannot delete {location}: {rm.stderr.strip()}")
                    failed = True
                    continue
            # aws s3 ls exits 1 with no output on an empty prefix: that is not an error.
            ls = aws("ls", "--recursive", location)
            if ls.returncode not in (0, 1) or ls.stderr.strip():
                print(f"tpch-clean: FAIL - cannot list {location}: {ls.stderr.strip()}")
                failed = True
            elif ls.stdout.strip():
                print(f"tpch-clean: FAIL - files left under {location}; delete them from CloudShell")
                failed = True
        spark.sql(f"DROP NAMESPACE IF EXISTS {catalog}.{ns}")
        print(f"tpch-clean: dropped namespace {catalog}.{ns}")
    spark.stop()
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
