#!/usr/bin/env bash
# Phase 1 acceptance test: S3 access from the spark container with the
# credentials of the VM instance profile.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "AWS CLI in the spark container"
docker compose exec -T spark bash -c 'aws s3 ls "s3://$S3_BUCKET/" >/dev/null && echo "  ok   - aws s3 ls on the bucket root"'

echo "Spark JVM with Iceberg S3FileIO"
status=0
out=$(docker compose exec -T spark spark-submit --conf spark.ui.enabled=false \
  /workspace/tests/s3_access.py 2>&1) || status=$?
grep -E '^  (ok|FAIL) ' <<<"$out" || true
if ((status != 0)); then
  if ! grep -q '^  FAIL ' <<<"$out"; then
    echo "  FAIL - spark-submit exited $status before a check failed. Its output:"
    grep -vE '^[0-9]{2}/[0-9]{2}/[0-9]{2} [0-9:]{8} INFO |^[[:space:]]+at |^[[:space:]]+\.\.\. [0-9]+ more' \
      <<<"$out" | tail -n 40 | sed 's/^/    /'
  fi
  exit "$status"
fi
