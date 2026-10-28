#!/usr/bin/env bash
# Checks the IAM templates: they render, they are valid JSON, and each one
# grants access only to the expected S3 prefixes.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
source "$ROOT/aws/lib.sh"

S3_BUCKET=test-bucket
ACCOUNT_ID=123456789012
VM_ROLE_ARN=arn:aws:iam::123456789012:role/lab-vm-role
POLARIS_EXTERNAL_ID=test-external-id

echo "render_template"
out=$(render_template <(printf '%s' '{"b":"${S3_BUCKET}/x"}'))
assert_eq "$out" '{"b":"test-bucket/x"}' "replaces a placeholder"
if (unset S3_BUCKET; render_template <(printf '%s' '${S3_BUCKET}') >/dev/null 2>&1); then
  fail "fails when a variable is unset"
else
  pass "fails when a variable is unset"
fi

echo "vm-role-policy.json"
vm=$(render_template "$ROOT/aws/iam/vm-role-policy.json")
jq -e . >/dev/null <<<"$vm" && pass "valid JSON" || fail "valid JSON"
assert_not_contains "$vm" '${' "no placeholder left"
rw=$(jq -r '[.Statement[] | select(.Sid == "ReadWriteLabObjects") | .Resource[]] | sort | join(",")' <<<"$vm")
assert_eq "$rw" "arn:aws:s3:::test-bucket/nessie/*,arn:aws:s3:::test-bucket/rest/*" "read/write only on nessie/ and rest/"
list=$(jq -r '[.Statement[] | select(.Sid == "ListLabPrefixes") | .Condition.StringLike."s3:prefix"[]] | sort | join(",")' <<<"$vm")
assert_eq "$list" ",nessie/*,polaris/*,rest/*" "list on bucket root and the three prefixes"
assume=$(jq -r '.Statement[] | select(.Sid == "AssumePolarisRole") | .Resource' <<<"$vm")
assert_eq "$assume" "arn:aws:iam::123456789012:role/polaris-s3-access" "may assume polaris-s3-access"

echo "polaris-role-policy.json"
pol=$(render_template "$ROOT/aws/iam/polaris-role-policy.json")
jq -e . >/dev/null <<<"$pol" && pass "valid JSON" || fail "valid JSON"
assert_not_contains "$pol" '${' "no placeholder left"
rw=$(jq -r '[.Statement[] | select(.Sid == "ReadWritePolarisObjects") | .Resource] | join(",")' <<<"$pol")
assert_eq "$rw" "arn:aws:s3:::test-bucket/polaris/*" "read/write only on polaris/"
list=$(jq -r '[.Statement[] | select(.Sid == "ListPolarisPrefix") | .Condition.StringLike."s3:prefix"[]] | join(",")' <<<"$pol")
assert_eq "$list" "polaris/*" "list only on polaris/"
assert_not_contains "$pol" "nessie/" "no access to nessie/"
assert_not_contains "$pol" "rest/" "no access to rest/"

echo "polaris-role-trust.json"
trust=$(render_template "$ROOT/aws/iam/polaris-role-trust.json")
jq -e . >/dev/null <<<"$trust" && pass "valid JSON" || fail "valid JSON"
principal=$(jq -r '.Statement[0].Principal.AWS' <<<"$trust")
assert_eq "$principal" "$VM_ROLE_ARN" "trusts the VM role only"
ext=$(jq -r '.Statement[0].Condition.StringEquals."sts:ExternalId"' <<<"$trust")
assert_eq "$ext" "test-external-id" "requires the external id"

finish
