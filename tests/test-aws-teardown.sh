#!/usr/bin/env bash
# Runs aws/teardown.sh against the stub AWS CLI and checks the calls it makes.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"

export PATH="$ROOT/tests/stubs:$PATH"
export AWS_REGION=eu-west-1 S3_BUCKET=test-bucket INSTANCE_ID=i-0123456789abcdef0
export AWS_STUB_LOG
AWS_STUB_LOG=$(mktemp)
trap 'rm -f "$AWS_STUB_LOG"' EXIT

echo "resources exist, user confirms"
: >"$AWS_STUB_LOG"
out=$(echo test-bucket | STUB_EXISTING=1 "$ROOT/aws/teardown.sh")
log=$(<"$AWS_STUB_LOG")
assert_contains "$log" "iam delete-role-policy --role-name lab-vm-role --policy-name iceberg-lab-vm" "removes the VM inline policy"
assert_contains "$log" "iam delete-role-policy --role-name polaris-s3-access --policy-name polaris-s3-access" "removes the Polaris role policy"
assert_contains "$log" "iam delete-role --role-name polaris-s3-access" "deletes the Polaris role"
assert_contains "$log" "s3 rb s3://test-bucket --force" "empties and deletes the bucket"
assert_not_contains "$log" "delete-role --role-name lab-vm-role" "keeps the VM role"
assert_contains "$out" "hop limit" "reminds about the hop limit"

echo "resources exist, user does not confirm"
: >"$AWS_STUB_LOG"
out=$(echo no | STUB_EXISTING=1 "$ROOT/aws/teardown.sh")
log=$(<"$AWS_STUB_LOG")
assert_not_contains "$log" "s3 rb" "keeps the bucket"
assert_contains "$out" "kept" "says the bucket was kept"

echo "nothing exists"
: >"$AWS_STUB_LOG"
out=$(STUB_EXISTING=0 "$ROOT/aws/teardown.sh" </dev/null)
log=$(<"$AWS_STUB_LOG")
assert_not_contains "$log" "delete-role" "deletes nothing"
assert_not_contains "$log" "s3 rb" "does not touch a missing bucket"

finish
