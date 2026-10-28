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


def describe(error):
    """The Java exception class and message, or the Python error."""
    java = getattr(error, "java_exception", None)
    return java.toString() if java is not None else repr(error)


def access_denied(error):
    """True when the Java cause chain holds the S3 error AccessDenied (HTTP 403)."""
    service_error = jvm.java.lang.Class.forName(
        "software.amazon.awssdk.awscore.exception.AwsServiceException")
    cause = getattr(error, "java_exception", None)
    while cause is not None:
        if service_error.isInstance(cause):
            return (cause.statusCode() == 403
                    and cause.awsErrorDetails().errorCode() == "AccessDenied")
        cause = cause.getCause()
    return False


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
try:
    write(allowed, token)
    check(read(allowed) == token, f"write and read back {allowed}")
    io.deleteFile(allowed)
    check(not io.newInputFile(allowed).exists(), f"delete {allowed}")
except Exception as error:
    check(False, f"write, read and delete {allowed}: {describe(error)}")
    try:
        io.deleteFile(allowed)  # best effort: do not leave the test object behind
    except Exception:
        pass

denied = f"s3://{bucket}/polaris/_smoke/{token}.txt"
try:
    write(denied, token)
except Exception as error:
    ok = access_denied(error)
    check(ok, f"write to {denied} is denied" + ("" if ok else f" (other error: {describe(error)})"))
else:
    check(False, f"write to {denied} is denied (it succeeded)")
    io.deleteFile(denied)  # remove the object that the VM role must not be able to write

spark.stop()
sys.exit(1 if failures else 0)
