#!/usr/bin/env bash
# Removes the AWS resources created by aws/setup.sh. Asks before deleting the bucket.
# Run it with administrative AWS credentials, not on the lab VM.
#
# Required: AWS_REGION, S3_BUCKET, INSTANCE_ID (the lab VM).
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib.sh"

: "${AWS_REGION:?set AWS_REGION}" "${S3_BUCKET:?set S3_BUCKET}" "${INSTANCE_ID:?set INSTANCE_ID}"
export AWS_DEFAULT_REGION=$AWS_REGION

VM_ROLE_NAME=$(vm_role_name "$INSTANCE_ID")

echo "==> Inline policy $VM_POLICY_NAME on VM role $VM_ROLE_NAME"
if aws iam get-role-policy --role-name "$VM_ROLE_NAME" --policy-name "$VM_POLICY_NAME" >/dev/null 2>&1; then
  aws iam delete-role-policy --role-name "$VM_ROLE_NAME" --policy-name "$VM_POLICY_NAME"
  echo "    deleted"
else
  echo "    not present"
fi

echo "==> Role $POLARIS_ROLE_NAME"
if aws iam get-role --role-name "$POLARIS_ROLE_NAME" >/dev/null 2>&1; then
  if aws iam get-role-policy --role-name "$POLARIS_ROLE_NAME" --policy-name "$POLARIS_POLICY_NAME" >/dev/null 2>&1; then
    aws iam delete-role-policy --role-name "$POLARIS_ROLE_NAME" --policy-name "$POLARIS_POLICY_NAME"
  fi
  aws iam delete-role --role-name "$POLARIS_ROLE_NAME"
  echo "    deleted"
else
  echo "    not present"
fi

echo "==> Bucket s3://$S3_BUCKET"
if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
  read -r -p "Type the bucket name to delete s3://$S3_BUCKET and all its objects: " answer || answer=
  if [[ $answer == "$S3_BUCKET" ]]; then
    aws s3 rb "s3://$S3_BUCKET" --force
    echo "    deleted"
  else
    echo "    kept (the answer did not match the bucket name)"
  fi
else
  echo "    not present"
fi

cat <<EOF

Not changed by this script, because setup.sh did not create them:
- the VM role $VM_ROLE_NAME and its instance profile;
- the IMDSv2 options of $INSTANCE_ID (hop limit 2). To restore hop limit 1:
  aws ec2 modify-instance-metadata-options --instance-id $INSTANCE_ID --http-put-response-hop-limit 1
EOF
