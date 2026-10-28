#!/usr/bin/env bash
# Runs aws/setup.sh against the stub AWS CLI and checks the calls it makes.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"

export PATH="$ROOT/tests/stubs:$PATH"
export AWS_REGION=eu-west-1 S3_BUCKET=test-bucket INSTANCE_ID=i-0123456789abcdef0
export AWS_STUB_LOG
AWS_STUB_LOG=$(mktemp)
trap 'rm -f "$AWS_STUB_LOG"' EXIT
unset POLARIS_EXTERNAL_ID

echo "first run on an empty account"
: >"$AWS_STUB_LOG"
out=$(STUB_EXISTING=0 "$ROOT/aws/setup.sh")
log=$(<"$AWS_STUB_LOG")
assert_contains "$log" "s3api create-bucket --bucket test-bucket --create-bucket-configuration LocationConstraint=eu-west-1" "creates the bucket in the region"
assert_contains "$log" "s3api put-public-access-block --bucket test-bucket --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" "blocks all public access"
assert_contains "$log" '"SSEAlgorithm":"AES256"' "enables SSE-S3"
assert_contains "$log" "iam put-role-policy --role-name lab-vm-role --policy-name iceberg-lab-vm" "adds the inline policy to the existing VM role"
assert_contains "$log" "iam create-role --role-name polaris-s3-access" "creates polaris-s3-access"
assert_contains "$log" "arn:aws:iam::123456789012:role/lab-vm-role" "trust policy names the VM role"
assert_contains "$log" "iam put-role-policy --role-name polaris-s3-access --policy-name polaris-s3-access" "puts the Polaris role policy"
assert_contains "$log" "ec2 modify-instance-metadata-options --instance-id i-0123456789abcdef0 --http-tokens required --http-put-response-hop-limit 2 --http-endpoint enabled" "sets IMDSv2 with hop limit 2"
assert_not_contains "$log" "update-assume-role-policy" "does not update a role it just created"
if [[ $out =~ POLARIS_EXTERNAL_ID=[0-9a-f]{32} ]]; then pass "prints a generated external id"; else fail "prints a generated external id"; fi
assert_contains "$out" "POLARIS_ROLE_ARN=arn:aws:iam::123456789012:role/polaris-s3-access" "prints the Polaris role ARN"
assert_contains "$out" "S3_BUCKET=test-bucket" "prints the bucket"

echo "second run, resources exist"
: >"$AWS_STUB_LOG"
out=$(STUB_EXISTING=1 "$ROOT/aws/setup.sh")
log=$(<"$AWS_STUB_LOG")
assert_not_contains "$log" "create-bucket" "keeps the existing bucket"
assert_not_contains "$log" "iam create-role" "keeps the existing role"
assert_contains "$log" "iam update-assume-role-policy --role-name polaris-s3-access" "updates the trust policy"
assert_contains "$log" "existing-external-id" "trust policy keeps the existing external id"
assert_contains "$out" "POLARIS_EXTERNAL_ID=existing-external-id" "prints the existing external id"

echo "explicit external id wins"
: >"$AWS_STUB_LOG"
out=$(STUB_EXISTING=1 POLARIS_EXTERNAL_ID=my-id "$ROOT/aws/setup.sh")
assert_contains "$out" "POLARIS_EXTERNAL_ID=my-id" "uses POLARIS_EXTERNAL_ID from the environment"

echo "us-east-1 has no location constraint"
: >"$AWS_STUB_LOG"
STUB_EXISTING=0 AWS_REGION=us-east-1 "$ROOT/aws/setup.sh" >/dev/null
log=$(<"$AWS_STUB_LOG")
assert_not_contains "$log" "LocationConstraint" "omits LocationConstraint in us-east-1"

echo "missing parameter"
if (unset S3_BUCKET; "$ROOT/aws/setup.sh" >/dev/null 2>&1); then fail "fails without S3_BUCKET"; else pass "fails without S3_BUCKET"; fi

finish
