"""Phase 1 acceptance test.

The Spark JVM reads and writes S3 with the credentials of the VM instance
profile (IMDSv2), through Iceberg S3FileIO: the same code path the catalogs use.
"""
import os
import sys
import uuid

from pyspark.sql import SparkSession

bucket = os.environ["S3_BUCKET"]
spark = SparkSession.builder.appName("s3-access-test").getOrCreate()
jvm = spark._jvm

props = jvm.java.util.HashMap()
props.put("client.region", os.environ["AWS_REGION"])
props.put("s3.path-style-access", os.environ.get("S3_PATH_STYLE_ACCESS", "false"))
if os.environ.get("S3_ENDPOINT"):
    props.put("s3.endpoint", os.environ["S3_ENDPOINT"])
io = jvm.org.apache.iceberg.aws.s3.S3FileIO()
io.initialize(props)

failures = 0


def check(ok, message):
    global failures
    print(("  ok   - " if ok else "  FAIL - ") + message)
    failures += 0 if ok else 1


def write(path, text):
    out = io.newOutputFile(path).createOrOverwrite()
    out.write(bytearray(text.encode()))
    out.close()


def read(path):
    stream = io.newInputFile(path).newStream()
    try:
        return bytes(stream.readAllBytes()).decode()
    finally:
        stream.close()


token = uuid.uuid4().hex
allowed = f"s3://{bucket}/rest/_smoke/{token}.txt"
write(allowed, token)
check(read(allowed) == token, f"write and read back {allowed}")
io.deleteFile(allowed)
check(not io.newInputFile(allowed).exists(), f"delete {allowed}")

denied = f"s3://{bucket}/polaris/_smoke/{token}.txt"
try:
    write(denied, token)
    check(False, f"write to {denied} is denied (it succeeded)")
except Exception as error:  # Py4JJavaError wraps the AWS SDK exception
    check("403" in str(error) or "AccessDenied" in str(error), f"write to {denied} is denied")

spark.stop()
sys.exit(1 if failures else 0)
