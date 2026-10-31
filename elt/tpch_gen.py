"""Generates the TPC-H tables as Parquet files with DuckDB (spec 2026-10-30-dbt-elt,
section 6.3). Usage: python3 tpch_gen.py SF OUTDIR. Does nothing when OUTDIR is complete."""
import pathlib
import sys

import duckdb

TABLES = ["region", "nation", "customer", "supplier", "part", "partsupp", "orders", "lineitem"]


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: tpch_gen.py SF OUTDIR")
    sf, out = sys.argv[1], pathlib.Path(sys.argv[2])
    try:
        scale = float(sf)
    except ValueError:
        sys.exit(f"tpch-gen: SF must be a number (got '{sf}')")
    if scale <= 0:
        sys.exit(f"tpch-gen: SF must be greater than 0 (got '{sf}')")
    if all((out / f"{t}.parquet").exists() for t in TABLES):
        print(f"tpch-gen: {out} is complete, nothing to do")
        return
    out.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()
    con.execute("SET autoinstall_known_extensions = false")
    con.execute(f"CALL dbgen(sf = {scale})")
    for t in TABLES:
        # Write to a temporary name first: a complete file always has its final name.
        tmp = out / f".{t}.parquet.tmp"
        con.execute(f"COPY {t} TO '{tmp}' (FORMAT parquet)")
        tmp.rename(out / f"{t}.parquet")
        print(f"tpch-gen: {out / t}.parquet")


if __name__ == "__main__":
    main()
