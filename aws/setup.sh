#!/usr/bin/env bash
# Creates or updates the AWS resources of the lab. Safe to run more than once.
# Run it with administrative AWS credentials (for example in AWS CloudShell),
# not on the lab VM.
#
# Required: AWS_REGION, S3_BUCKET, INSTANCE_ID (the existing lab VM).
# Optional: POLARIS_EXTERNAL_ID. When absent, the value in the existing
# polaris-s3-access trust policy is reused, or a new one is generated.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

: "${AWS_REGION:?set AWS_REGION}" "${S3_BUCKET:?set S3_BUCKET}" "${INSTANCE_ID:?set INSTANCE_ID}"
export AWS_DEFAULT_REGION=$AWS_REGION

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
VM_ROLE_NAME=$(vm_role_name "$INSTANCE_ID")
VM_ROLE_ARN=$(aws iam get-role --role-name "$VM_ROLE_NAME" --query Role.Arn --output text)
POLARIS_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${POLARIS_ROLE_NAME}"

echo "==> Bucket s3://$S3_BUCKET"
if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
  echo "    exists"
elif [[ $AWS_REGION == us-east-1 ]]; then
  aws s3api create-bucket --bucket "$S3_BUCKET" >/dev/null
  echo "    created"
else
  aws s3api create-bucket --bucket "$S3_BUCKET" \
    --create-bucket-configuration "LocationConstraint=$AWS_REGION" >/dev/null
  echo "    created"
fi
aws s3api put-public-access-block --bucket "$S3_BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$S3_BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
echo "    public access blocked, SSE-S3 enabled"

echo "==> Inline policy $VM_POLICY_NAME on VM role $VM_ROLE_NAME"
vm_policy=$(render_template "$SCRIPT_DIR/iam/vm-role-policy.json")
aws iam put-role-policy --role-name "$VM_ROLE_NAME" --policy-name "$VM_POLICY_NAME" \
  --policy-document "$vm_policy"
echo "    applied"

echo "==> Role $POLARIS_ROLE_NAME"
if aws iam get-role --role-name "$POLARIS_ROLE_NAME" >/dev/null 2>&1; then
  if [[ -z ${POLARIS_EXTERNAL_ID:-} ]]; then
    POLARIS_EXTERNAL_ID=$(aws iam get-role --role-name "$POLARIS_ROLE_NAME" \
      --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals."sts:ExternalId"' \
      --output text)
    [[ $POLARIS_EXTERNAL_ID == None ]] && POLARIS_EXTERNAL_ID=
  fi
  : "${POLARIS_EXTERNAL_ID:=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')}"
  trust_policy=$(render_template "$SCRIPT_DIR/iam/polaris-role-trust.json")
  aws iam update-assume-role-policy --role-name "$POLARIS_ROLE_NAME" \
    --policy-document "$trust_policy"
  echo "    trust policy updated"
else
  : "${POLARIS_EXTERNAL_ID:=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')}"
  trust_policy=$(render_template "$SCRIPT_DIR/iam/polaris-role-trust.json")
  aws iam create-role --role-name "$POLARIS_ROLE_NAME" \
    --description "Iceberg lab: Polaris credential vending on the polaris/ prefix" \
    --assume-role-policy-document "$trust_policy" >/dev/null
  echo "    created"
fi
polaris_policy=$(render_template "$SCRIPT_DIR/iam/polaris-role-policy.json")
aws iam put-role-policy --role-name "$POLARIS_ROLE_NAME" --policy-name "$POLARIS_POLICY_NAME" \
  --policy-document "$polaris_policy"
echo "    policy applied"

echo "==> Instance metadata options on $INSTANCE_ID"
aws ec2 modify-instance-metadata-options --instance-id "$INSTANCE_ID" \
  --http-tokens required --http-put-response-hop-limit 2 --http-endpoint enabled >/dev/null
echo "    IMDSv2 required, hop limit 2"

cat <<EOF

Done. Copy these lines into .env on the lab VM:

S3_BUCKET=$S3_BUCKET
AWS_REGION=$AWS_REGION
POLARIS_ROLE_ARN=$POLARIS_ROLE_ARN
POLARIS_EXTERNAL_ID=$POLARIS_EXTERNAL_ID
EOF
