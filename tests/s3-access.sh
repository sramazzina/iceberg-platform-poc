#!/usr/bin/env bash
# Phase 1 acceptance test: S3 access from the spark container with the
# credentials of the VM instance profile.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "AWS CLI in the spark container"
docker compose exec -T spark bash -c 'aws s3 ls "s3://$S3_BUCKET/" >/dev/null && echo "  ok   - aws s3 ls on the bucket root"'

echo "Spark JVM with Iceberg S3FileIO"
docker compose exec -T spark spark-submit --conf spark.ui.enabled=false /workspace/tests/s3_access.py 2>&1 \
  | grep -E '^  (ok|FAIL) '
