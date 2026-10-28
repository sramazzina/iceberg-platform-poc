# Iceberg catalog lab — Stage 1 (AWS scripts) and Phase 1 (Spark + Postgres) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the AWS provisioning scripts (tested against a stub AWS CLI) and the Phase 1 lab stack (Postgres + Spark image with Iceberg) that reads and writes S3 with the VM instance-profile credentials.

**Architecture:** Bash scripts in `aws/` render IAM JSON templates with a pure-bash helper and call the AWS CLI; tests run them against a stub `aws` on `PATH`. Phase 1 adds a Docker Compose stack with `postgres` and a custom `spark` image (official `apache/spark` base + Iceberg runtime + AWS bundle + JupyterLab); the acceptance test uses Iceberg `S3FileIO` from the Spark JVM.

**Tech Stack:** Bash, AWS CLI v2, jq, Docker Compose, Apache Spark, Apache Iceberg, JupyterLab, PostgreSQL.

**Spec:** `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md`

---

## Conventions for every task

- All file content, comments, commit messages: English.
- Commit messages: Conventional Commits style, **no `Co-Authored-By` line**.
- Do not push. The controller pushes batches and opens the PR.
- Never write a real account ID, bucket name, ARN, external ID, password or secret into a tracked file. Tests use the fake values `123456789012`, `test-bucket`, `lab-vm-role`, `test-external-id`.
- Stage 1 tasks (1-6) run on the developer workstation. They need `bash`, `jq`, `make`, `git`. They do not need AWS or Docker.
- Phase 1 tasks (7-9) run on the EC2 VM. They need Docker with the Compose plugin and a `.env` filled from `aws/setup.sh` output.

## File map

| File | Responsibility | Task |
|---|---|---|
| `Makefile` | Entry points for lint, tests, stack lifecycle | 1, 3, 4, 9 |
| `tests/lib/assert.sh` | Assertion helpers for bash tests | 1 |
| `tests/lint.sh` | Static checks: bash syntax, JSON syntax, Compose config | 1 |
| `aws/lib.sh` | `render_template`, `vm_role_name`, shared constants | 2 |
| `aws/iam/*.json` | IAM policy templates with `${VAR}` placeholders | 2 |
| `tests/test-iam-policies.sh` | Template rendering and least-privilege checks | 2 |
| `tests/stubs/aws` | Stub AWS CLI that logs calls | 3 |
| `aws/setup.sh` | Idempotent creation of bucket, policies, role, IMDS options | 3 |
| `tests/test-aws-setup.sh` | Tests `setup.sh` against the stub | 3 |
| `aws/teardown.sh` | Removal of everything `setup.sh` created | 4 |
| `tests/test-aws-teardown.sh` | Tests `teardown.sh` against the stub | 4 |
| `aws/README-aws.md`, `.env.example`, `NOTES.md` | AWS runbook, env template, deviations | 5 |
| `VERSIONS.md` | Pinned versions with sources | 6 |
| `postgres/init/01-create-databases.sh`, `docker-compose.yml` | Postgres with `polaris` and `nessie` databases | 7 |
| `spark/Dockerfile`, `spark/entrypoint.sh`, `spark/conf/spark-defaults.conf` | Spark image | 8 |
| `tests/s3_access.py`, `tests/s3-access.sh` | Phase 1 acceptance test | 9 |

---

## Task 1: Repository scaffolding and lint

**Files:**
- Create: `Makefile`
- Create: `tests/lib/assert.sh`
- Create: `tests/lint.sh`

- [ ] **Step 1: Create the assertion helpers**

`tests/lib/assert.sh`:

```bash
# Minimal assertion helpers for bash tests. Source this file; do not run it.

FAILURES=0

pass() { echo "  ok   - $1"; }
fail() { echo "  FAIL - $1"; FAILURES=$((FAILURES + 1)); }

# assert_eq ACTUAL EXPECTED MESSAGE
assert_eq() {
  if [[ $1 == "$2" ]]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

# assert_contains HAYSTACK NEEDLE MESSAGE
assert_contains() {
  if [[ $1 == *"$2"* ]]; then pass "$3"; else fail "$3 (missing '$2')"; fi
}

# assert_not_contains HAYSTACK NEEDLE MESSAGE
assert_not_contains() {
  if [[ $1 != *"$2"* ]]; then pass "$3"; else fail "$3 (unexpected '$2')"; fi
}

# finish: exit 1 when at least one assertion failed.
finish() {
  if ((FAILURES > 0)); then
    echo "$FAILURES assertion(s) failed"
    exit 1
  fi
  echo "all assertions passed"
}
```

- [ ] **Step 2: Create the lint script**

`tests/lint.sh`:

```bash
#!/usr/bin/env bash
# Static checks that need no AWS access: bash syntax, JSON syntax, Compose file.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0

while IFS= read -r -d '' f; do
  bash -n "$f" || { echo "bash syntax error: $f"; status=1; }
done < <(find . -path ./.git -prune -o \( -name '*.sh' -o -path ./tests/stubs/aws \) -type f -print0)

while IFS= read -r -d '' f; do
  jq empty "$f" || { echo "invalid JSON: $f"; status=1; }
done < <(find . -path ./.git -prune -o -name '*.json' -type f -print0)

if [[ -f docker-compose.yml ]]; then
  env_file=.env
  [[ -f $env_file ]] || env_file=.env.example
  docker compose --env-file "$env_file" config --quiet || { echo "invalid docker-compose.yml"; status=1; }
fi

if ((status == 0)); then echo "lint passed"; fi
exit $status
```

Run: `chmod +x tests/lint.sh`

- [ ] **Step 3: Create the Makefile**

`Makefile` (recipe lines start with a TAB):

```make
.PHONY: lint test-aws

lint:
	tests/lint.sh
```

- [ ] **Step 4: Verify that lint detects a syntax error**

Run:
```bash
printf 'if then\n' > broken.sh
make lint; echo "exit=$?"
rm broken.sh
```
Expected: output contains `bash syntax error: ./broken.sh` and `exit=2` (make reports the failing recipe).

- [ ] **Step 5: Verify that lint passes on the clean tree**

Run: `make lint`
Expected: `lint passed`

- [ ] **Step 6: Commit**

```bash
git add Makefile tests/lib/assert.sh tests/lint.sh
git commit -m "chore: add lint script, test helpers and Makefile"
```

---

## Task 2: IAM policy templates and rendering helper

**Files:**
- Create: `aws/lib.sh`
- Create: `aws/iam/vm-role-policy.json`
- Create: `aws/iam/polaris-role-policy.json`
- Create: `aws/iam/polaris-role-trust.json`
- Test: `tests/test-iam-policies.sh`
- Modify: `Makefile`

- [ ] **Step 1: Write the failing test**

`tests/test-iam-policies.sh`:

```bash
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
```

Run: `chmod +x tests/test-iam-policies.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/test-iam-policies.sh`
Expected: FAIL — `aws/lib.sh: No such file or directory`.

- [ ] **Step 3: Write `aws/lib.sh`**

```bash
# Shared helpers for aws/setup.sh and aws/teardown.sh. Source this file; do not run it.

VM_POLICY_NAME=iceberg-lab-vm
POLARIS_ROLE_NAME=polaris-s3-access
POLARIS_POLICY_NAME=polaris-s3-access

# render_template FILE
# Prints FILE with every ${NAME} placeholder replaced by the value of the shell
# variable NAME. Returns 1 when a placeholder has no value.
render_template() {
  local content name
  content=$(<"$1")
  while [[ $content =~ \$\{([A-Z_][A-Z0-9_]*)\} ]]; do
    name=${BASH_REMATCH[1]}
    if [[ -z ${!name:-} ]]; then
      echo "render_template: variable $name is not set (in $1)" >&2
      return 1
    fi
    content=${content//"\${$name}"/"${!name}"}
  done
  printf '%s\n' "$content"
}

# vm_role_name INSTANCE_ID
# Prints the name of the IAM role in the instance profile of the instance.
vm_role_name() {
  local profile_arn
  profile_arn=$(aws ec2 describe-instances --instance-ids "$1" \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text)
  if [[ -z $profile_arn || $profile_arn == None ]]; then
    echo "Instance $1 has no instance profile. Attach one, then run again." >&2
    return 1
  fi
  aws iam get-instance-profile --instance-profile-name "${profile_arn##*/}" \
    --query 'InstanceProfile.Roles[0].RoleName' --output text
}
```

- [ ] **Step 4: Write the three IAM templates**

`aws/iam/vm-role-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListLabPrefixes",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${S3_BUCKET}",
      "Condition": {
        "StringLike": { "s3:prefix": ["", "polaris/*", "nessie/*", "rest/*"] }
      }
    },
    {
      "Sid": "BucketLocation",
      "Effect": "Allow",
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:aws:s3:::${S3_BUCKET}"
    },
    {
      "Sid": "ReadWriteLabObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}/nessie/*",
        "arn:aws:s3:::${S3_BUCKET}/rest/*"
      ]
    },
    {
      "Sid": "AssumePolarisRole",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/polaris-s3-access"
    }
  ]
}
```

`aws/iam/polaris-role-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListPolarisPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${S3_BUCKET}",
      "Condition": {
        "StringLike": { "s3:prefix": ["polaris/*"] }
      }
    },
    {
      "Sid": "BucketLocation",
      "Effect": "Allow",
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:aws:s3:::${S3_BUCKET}"
    },
    {
      "Sid": "ReadWritePolarisObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::${S3_BUCKET}/polaris/*"
    }
  ]
}
```

`aws/iam/polaris-role-trust.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "${VM_ROLE_ARN}" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": { "sts:ExternalId": "${POLARIS_EXTERNAL_ID}" }
      }
    }
  ]
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `tests/test-iam-policies.sh`
Expected: every line `ok`, last line `all assertions passed`.

- [ ] **Step 6: Add the test to the Makefile**

Replace the `Makefile` content with:

```make
.PHONY: lint test-aws

lint:
	tests/lint.sh

test-aws:
	tests/test-iam-policies.sh
```

Run: `make lint test-aws`
Expected: `lint passed` and `all assertions passed`.

- [ ] **Step 7: Commit**

```bash
git add aws/lib.sh aws/iam tests/test-iam-policies.sh Makefile
git commit -m "feat(aws): add IAM policy templates and rendering helper"
```

---

## Task 3: `aws/setup.sh` with a stub-based test

**Files:**
- Create: `tests/stubs/aws`
- Create: `tests/test-aws-setup.sh`
- Create: `aws/setup.sh`
- Modify: `Makefile`

- [ ] **Step 1: Write the stub AWS CLI**

`tests/stubs/aws`:

```bash
#!/usr/bin/env bash
# Test double for the AWS CLI. Appends every call to $AWS_STUB_LOG and answers
# the read calls of aws/setup.sh and aws/teardown.sh.
# STUB_EXISTING=1 simulates an account where the lab resources already exist.
echo "$*" >>"$AWS_STUB_LOG"

exists() { [[ ${STUB_EXISTING:-0} == 1 ]]; }
missing() { echo "An error occurred (NoSuchEntity)" >&2; exit 254; }

case "$1 $2" in
  "sts get-caller-identity") echo 123456789012 ;;
  "ec2 describe-instances") echo "arn:aws:iam::123456789012:instance-profile/lab-vm-profile" ;;
  "iam get-instance-profile") echo lab-vm-role ;;
  "s3api head-bucket") exists || missing ;;
  "iam get-role-policy") exists || missing ;;
  "iam get-role")
    if [[ $* == *"--role-name lab-vm-role"* ]]; then
      echo "arn:aws:iam::123456789012:role/lab-vm-role"
    elif exists; then
      if [[ $* == *ExternalId* ]]; then echo existing-external-id; else echo "{}"; fi
    else
      missing
    fi
    ;;
esac
exit 0
```

Run: `chmod +x tests/stubs/aws`

- [ ] **Step 2: Write the failing test**

`tests/test-aws-setup.sh`:

```bash
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
```

Run: `chmod +x tests/test-aws-setup.sh`

- [ ] **Step 3: Run the test to verify it fails**

Run: `tests/test-aws-setup.sh`
Expected: FAIL — `aws/setup.sh: No such file or directory`.

- [ ] **Step 4: Write `aws/setup.sh`**

```bash
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
aws iam put-role-policy --role-name "$VM_ROLE_NAME" --policy-name "$VM_POLICY_NAME" \
  --policy-document "$(render_template "$SCRIPT_DIR/iam/vm-role-policy.json")"
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
  aws iam update-assume-role-policy --role-name "$POLARIS_ROLE_NAME" \
    --policy-document "$(render_template "$SCRIPT_DIR/iam/polaris-role-trust.json")"
  echo "    trust policy updated"
else
  : "${POLARIS_EXTERNAL_ID:=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')}"
  aws iam create-role --role-name "$POLARIS_ROLE_NAME" \
    --description "Iceberg lab: Polaris credential vending on the polaris/ prefix" \
    --assume-role-policy-document "$(render_template "$SCRIPT_DIR/iam/polaris-role-trust.json")" >/dev/null
  echo "    created"
fi
aws iam put-role-policy --role-name "$POLARIS_ROLE_NAME" --policy-name "$POLARIS_POLICY_NAME" \
  --policy-document "$(render_template "$SCRIPT_DIR/iam/polaris-role-policy.json")"
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
```

Run: `chmod +x aws/setup.sh`

Note: `render_template` reads `ACCOUNT_ID`, `S3_BUCKET`, `VM_ROLE_ARN` and `POLARIS_EXTERNAL_ID` as shell variables; they are set above before each call.

- [ ] **Step 5: Run the test to verify it passes**

Run: `tests/test-aws-setup.sh`
Expected: every line `ok`, last line `all assertions passed`.

- [ ] **Step 6: Add the test to the Makefile**

In `Makefile`, add a line under `test-aws:` so the target reads:

```make
test-aws:
	tests/test-iam-policies.sh
	tests/test-aws-setup.sh
```

Run: `make lint test-aws`
Expected: `lint passed`, then `all assertions passed` twice.

- [ ] **Step 7: Commit**

```bash
git add tests/stubs/aws tests/test-aws-setup.sh aws/setup.sh Makefile
git commit -m "feat(aws): add idempotent setup script"
```

---

## Task 4: `aws/teardown.sh` with a stub-based test

**Files:**
- Create: `tests/test-aws-teardown.sh`
- Create: `aws/teardown.sh`
- Modify: `Makefile`

- [ ] **Step 1: Write the failing test**

`tests/test-aws-teardown.sh`:

```bash
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
```

Run: `chmod +x tests/test-aws-teardown.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/test-aws-teardown.sh`
Expected: FAIL — `aws/teardown.sh: No such file or directory`.

- [ ] **Step 3: Write `aws/teardown.sh`**

```bash
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
```

Run: `chmod +x aws/teardown.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `tests/test-aws-teardown.sh`
Expected: every line `ok`, last line `all assertions passed`.

- [ ] **Step 5: Add the test to the Makefile**

The `test-aws` target becomes:

```make
test-aws:
	tests/test-iam-policies.sh
	tests/test-aws-setup.sh
	tests/test-aws-teardown.sh
```

Run: `make lint test-aws`
Expected: `lint passed`, then `all assertions passed` three times.

- [ ] **Step 6: Commit**

```bash
git add tests/test-aws-teardown.sh aws/teardown.sh Makefile
git commit -m "feat(aws): add teardown script"
```

---
## Task 5: Environment template, secret check, NOTES.md, AWS runbook

**Files:**
- Create: `tests/check-no-secrets.sh`
- Create: `.env.example`
- Create: `NOTES.md`
- Create: `aws/README-aws.md`
- Modify: `Makefile`

- [ ] **Step 1: Write the secret check**

`tests/check-no-secrets.sh`:

```bash
#!/usr/bin/env bash
# Fails when the repository holds a credential or an account-specific value.
# Scans tracked files and untracked files that are not git-ignored.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0
for path in .env secrets; do
  if [[ -n $(git ls-files -- "$path") ]]; then
    echo "tracked file under $path"
    status=1
  fi
done

# AWS access key ids and real account ids in ARNs. 123456789012 is the fake test account.
matches=$(git ls-files -z -co --exclude-standard \
  | xargs -0 grep -nIE 'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|arn:aws:[a-z0-9-]+::[0-9]{12}' 2>/dev/null \
  | grep -v '123456789012' || true)
if [[ -n $matches ]]; then
  echo "possible credential or account id:"
  echo "$matches"
  status=1
fi

if ((status == 0)); then echo "no secrets found"; fi
exit $status
```

Run: `chmod +x tests/check-no-secrets.sh`

- [ ] **Step 2: Verify that the check detects a leaked key**

Run:
```bash
echo "key=AKIA$(printf 'X%.0s' {1..16})" > leak.txt
tests/check-no-secrets.sh; echo "exit=$?"
rm leak.txt
tests/check-no-secrets.sh
```
Expected: first run prints `leak.txt:1:key=AKIAXXXXXXXXXXXXXXXX` and `exit=1`; second run prints `no secrets found`. (The fake key is built at run time, so this plan file does not trip the check.)

- [ ] **Step 3: Add the check to `make lint`**

The `lint` target becomes:

```make
lint:
	tests/lint.sh
	tests/check-no-secrets.sh
```

- [ ] **Step 4: Write `.env.example`**

```bash
# Lab configuration. Copy this file to .env and fill it in.
# .env is git-ignored. Never commit real values.

# ---- S3 storage --------------------------------------------------------------
# Bucket and region: copy them from the output of aws/setup.sh.
S3_BUCKET=
AWS_REGION=eu-west-1
# Empty on AWS. On-premise S3-compatible storage: http://<host>:<port>
S3_ENDPOINT=
# false on AWS, true for MinIO and RustFS.
S3_PATH_STYLE_ACCESS=false
# Empty on AWS: the containers use the VM instance profile through IMDSv2.
# Required on-premise, where there is no IMDS.
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=

# ---- Polaris credential vending (from the output of aws/setup.sh) ------------
POLARIS_ROLE_ARN=
POLARIS_EXTERNAL_ID=

# ---- Local secrets (choose your own values) ----------------------------------
POSTGRES_PASSWORD=change-me
POLARIS_DB_PASSWORD=change-me
NESSIE_DB_PASSWORD=change-me
POLARIS_ROOT_CLIENT_ID=root
POLARIS_ROOT_CLIENT_SECRET=change-me
JUPYTER_TOKEN=change-me

# ---- Host user ---------------------------------------------------------------
# Output of `id -u` on the VM. The spark container runs with this UID so that
# notebooks saved in scenarios/ stay editable on the host.
LAB_UID=1000

# ---- Pinned versions (sources in VERSIONS.md) --------------------------------
POSTGRES_IMAGE=postgres:18.6
SPARK_BASE_IMAGE=apache/spark:4.1.3-scala2.13-java17-python3-ubuntu
ICEBERG_VERSION=1.11.0
ICEBERG_SPARK_RUNTIME_ARTIFACT=iceberg-spark-runtime-4.1_2.13
ICEBERG_SPARK_RUNTIME_SHA1=f9b1e4a18797c58ae406104ef5c75d1b64a373c5
ICEBERG_AWS_BUNDLE_SHA1=afe5b22dd5bc2d2c0639049b06a92dae2545cac7
AWSCLI_VERSION=2.39.0
POLARIS_IMAGE=apache/polaris:1.8.0
POLARIS_ADMIN_TOOL_IMAGE=apache/polaris-admin-tool:1.8.0
POLARIS_SETUP_IMAGE=alpine/curl:8.22.0
NESSIE_IMAGE=ghcr.io/projectnessie/nessie:0.109.0
REST_FIXTURE_IMAGE=apache/iceberg-rest-fixture:1.10.1
```

- [ ] **Step 5: Write `NOTES.md`**

```markdown
# Notes

Deviations from the requirements (`docs/req/prompt-agente-lab-iceberg-polaris-nessie.md`)
and conflicts between the requirements and the project documentation.
Each entry: what the requirement says, what the lab does, and why.

## Deviations

### D1 — Repository root name
- Requirement (section 7): the root folder is `iceberg-catalog-lab/`.
- Lab: the root is the repository `iceberg-platform-poc`.
- Why: the repository already existed with this name. The layout below the root follows section 7.

### D2 — `aws/setup.sh` uses the existing VM role
- Requirement (section 6.4): `setup.sh` creates the instance profile.
- Lab: the VM and its instance profile already exist. `setup.sh` finds the VM role
  from `INSTANCE_ID` and adds the inline policy `iceberg-lab-vm` to it.
  `teardown.sh` removes only that inline policy.
- Why: the VM was created before the lab, with its own role.

### D3 — The VM role can list `polaris/`
- Requirement (section 6.1): the VM role has S3 access to `nessie/` and `rest/`.
- Lab: the VM role can also **list** (not read, not write) `polaris/` and the bucket root.
- Why: scenario 2 and the smoke tests use `aws s3 ls` to show the Polaris layout.
  Reads and writes under `polaris/` still need credentials vended by Polaris.

### D4 — Phase 1 test object prefix
- Requirement (phase 1): read and write a test file in `s3://${S3_BUCKET}/`.
- Lab: the test writes under `s3://${S3_BUCKET}/rest/_smoke/`.
- Why: the VM role has no write access to the bucket root (least privilege).

### D5 — Python packages are pinned in `spark/requirements.txt`
- Requirement (rule 4.2): pin every version in `.env`.
- Lab: image tags and JAR versions are in `.env`; Python packages are in `spark/requirements.txt`.
- Why: pip reads a requirements file natively; one build argument per package would add noise.

### D6 — Python 3.10 in the Spark image
- The official `apache/spark:4.1.3` images are based on Ubuntu 22.04, so Python is 3.10.
  Python 3.10 reaches end of life in October 2026. pandas and pyarrow are pinned to the
  last releases that support Python 3.10 (2.3.3 and 25.0.1). Accepted for a test lab.

### D7 — Iceberg client 1.11.0, not the latest 1.12.0
- Polaris 1.8.0 and Nessie 0.109.0 are built against Iceberg 1.11.0. The lab uses the same
  client version, so that compatibility is not a variable in the comparison.

## Open investigations

Filled in during phases 2-4.

- Polaris `relational-jdbc` bootstrap (admin tool job).
- Polaris credential vending against S3-compatible on-premise storage (`stsUnavailable`, `stsEndpoint`).
- Nessie credential vending (`client-iam`, `server-iam`).
- `apache/iceberg-rest-fixture`: no tag matches Iceberg 1.11; the lab uses 1.10.1.
```

- [ ] **Step 6: Write `aws/README-aws.md`**

````markdown
# AWS resources for the lab

The scripts in this folder create and remove the AWS resources of the lab.
Run them with administrative AWS credentials, for example in AWS CloudShell.
Do not run them on the lab VM: the VM role cannot create IAM roles.

## VM sizing

| Item | Recommendation |
|---|---|
| Instance type | 4 vCPU and 16 GB RAM minimum, for example `m6i.xlarge` or `t3.xlarge` |
| Disk | 50 GB gp3 |
| Operating system | Ubuntu Server 24.04 LTS |
| Network | Security group: inbound TCP 22 from your IP only. With SSM: no inbound port |
| IAM | An instance profile with a role. `setup.sh` adds the lab policy to this role |

## Software on the VM

1. Install Docker Engine and the Compose plugin from the Docker apt repository:
   <https://docs.docker.com/engine/install/ubuntu/>
2. Add your user to the `docker` group: `sudo usermod -aG docker $USER`. Log out and in again.
3. Install the AWS CLI v2: <https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html>
4. Check: `docker compose version` and `aws --version`.

## What `setup.sh` creates

| Resource | Detail |
|---|---|
| S3 bucket `${S3_BUCKET}` | Block Public Access on, default encryption SSE-S3 |
| Inline policy `iceberg-lab-vm` on the VM role | S3 read/write on `nessie/` and `rest/`, list on `polaris/`, `sts:AssumeRole` on `polaris-s3-access` |
| IAM role `polaris-s3-access` | Trusted by the VM role with an external ID. S3 read/write on `polaris/` only |
| VM metadata options | IMDSv2 required, `HttpPutResponseHopLimit=2` |

The hop limit must be 2: containers on a Docker bridge network are one extra network hop
from the instance metadata service. With hop limit 1 they do not receive IMDSv2 tokens, so
they get no credentials. Source:
<https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html>

## Run `setup.sh`

1. Open AWS CloudShell in the region of the VM.
2. Clone the repository: `git clone https://github.com/sramazzina/iceberg-platform-poc.git`
3. Go to the folder: `cd iceberg-platform-poc`
4. Set the parameters:
   ```bash
   export AWS_REGION=<region of the VM>
   export S3_BUCKET=<globally unique bucket name>
   export INSTANCE_ID=<id of the lab VM>
   ```
5. Run the script: `aws/setup.sh`
6. Copy the four lines printed at the end into `.env` on the VM.

The script is idempotent. Run it again after a change: it keeps the bucket, the role and the
external ID.

## Check from the VM

Run on the VM:

```bash
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/
aws s3 ls "s3://$S3_BUCKET/"
```

The second command prints the VM role name. The third command succeeds (the bucket is empty at first).

## Run `teardown.sh`

1. Stop the lab on the VM: `make down`.
2. In CloudShell, set `AWS_REGION`, `S3_BUCKET`, `INSTANCE_ID` as for `setup.sh`.
3. Run the script: `aws/teardown.sh`
4. Type the bucket name when the script asks for it. Any other answer keeps the bucket.

The script does not delete the VM role and does not change the hop limit, because `setup.sh`
did not create them.

## Costs

- The VM costs money while it runs. Stop it when you do not use the lab.
- An EBS volume costs money while it exists, also when the VM is stopped.
- S3 storage and requests cost money. `teardown.sh` deletes the bucket.
- IAM roles and policies are free.
````

- [ ] **Step 7: Run lint and the secret check**

Run: `make lint`
Expected: `lint passed` and `no secrets found`.

- [ ] **Step 8: Commit**

```bash
git add tests/check-no-secrets.sh .env.example NOTES.md aws/README-aws.md Makefile
git commit -m "docs: add env template, deviations notes, AWS runbook and secret check"
```

---

## Task 6: `VERSIONS.md`

**Files:**
- Create: `VERSIONS.md`

- [ ] **Step 1: Write `VERSIONS.md`**

```markdown
# Versions

Verification date: 2026-10-28. Every value is pinned in `.env.example`
(image tags, JAR versions, checksums) or in `spark/requirements.txt` (Python packages).
The tag `latest` is never used.

## Components

| Component | Version | Pinned in | Source |
|---|---|---|---|
| Apache Spark | 4.1.3 (Scala 2.13, Java 17) | `SPARK_BASE_IMAGE=apache/spark:4.1.3-scala2.13-java17-python3-ubuntu` | <https://hub.docker.com/r/apache/spark/tags>, <https://github.com/apache/spark-docker/tree/master/4.1.3/scala2.13-java17-python3-ubuntu> |
| Apache Iceberg Spark runtime | 1.11.0 | `ICEBERG_SPARK_RUNTIME_ARTIFACT=iceberg-spark-runtime-4.1_2.13`, `ICEBERG_VERSION`, `ICEBERG_SPARK_RUNTIME_SHA1` | <https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-4.1_2.13/1.11.0/> |
| Apache Iceberg AWS bundle | 1.11.0 | `ICEBERG_VERSION`, `ICEBERG_AWS_BUNDLE_SHA1` | <https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/1.11.0/> |
| Apache Polaris | 1.8.0 | `POLARIS_IMAGE=apache/polaris:1.8.0` | <https://github.com/apache/polaris/releases/tag/apache-polaris-1.8.0> |
| Apache Polaris admin tool | 1.8.0 | `POLARIS_ADMIN_TOOL_IMAGE=apache/polaris-admin-tool:1.8.0` | <https://hub.docker.com/r/apache/polaris-admin-tool/tags> |
| Project Nessie | 0.109.0 | `NESSIE_IMAGE=ghcr.io/projectnessie/nessie:0.109.0` | <https://github.com/projectnessie/nessie/releases/tag/nessie-0.109.0> |
| Iceberg REST fixture | 1.10.1 | `REST_FIXTURE_IMAGE=apache/iceberg-rest-fixture:1.10.1` | <https://hub.docker.com/r/apache/iceberg-rest-fixture/tags> |
| PostgreSQL | 18.6 | `POSTGRES_IMAGE=postgres:18.6` | <https://hub.docker.com/_/postgres> |
| curl + jq job image | alpine/curl 8.22.0 (jq added with `apk`) | `POLARIS_SETUP_IMAGE=alpine/curl:8.22.0` | <https://hub.docker.com/r/alpine/curl/tags> |
| AWS CLI v2 | 2.39.0 | `AWSCLI_VERSION` | <https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst> |
| Python (Spark image) | 3.10 (Ubuntu 22.04 package) | base image | <https://github.com/apache/spark-docker/tree/master/4.1.3/scala2.13-java17-python3-ubuntu> |
| JupyterLab | 4.6.4 | `spark/requirements.txt` | <https://pypi.org/project/jupyterlab/4.6.4/> |
| PyIceberg | 0.12.0 | `spark/requirements.txt` | <https://pypi.org/project/pyiceberg/0.12.0/> |
| pandas | 2.3.3 (last release for Python 3.10) | `spark/requirements.txt` | <https://pypi.org/project/pandas/2.3.3/> |
| pyarrow | 25.0.1 (last release for Python 3.10) | `spark/requirements.txt` | <https://pypi.org/project/pyarrow/25.0.1/> |
| requests | 2.34.2 | `spark/requirements.txt` | <https://pypi.org/project/requests/2.34.2/> |

## Compatibility

| Check | Result | Source |
|---|---|---|
| Iceberg 1.11.0 ships a runtime for Spark 4.1 / Scala 2.13 | Yes | <https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-4.1_2.13/maven-metadata.xml> |
| Newest Spark line with an Iceberg runtime on Maven Central | 4.1 (no `iceberg-spark-runtime-4.2_2.13` artifact) | <https://repo1.maven.org/maven2/org/apache/iceberg/> |
| Iceberg version Polaris 1.8.0 is built against | 1.11.0 | <https://github.com/apache/polaris/blob/apache-polaris-1.8.0/gradle/libs.versions.toml> |
| Iceberg version Nessie 0.109.0 is built against | 1.11.0 | <https://github.com/projectnessie/nessie/blob/nessie-0.109.0/gradle/libs.versions.toml> |
| Spark versions the Polaris Spark plugin targets | 3.5, 4.0 (not 4.1). The lab uses the plain Iceberg REST client, not the Polaris plugin | same Polaris file |
| Postgres version used in the Polaris JDBC guide | 18.6 | <https://github.com/apache/polaris/blob/apache-polaris-1.8.0/site/content/guides/assets/postgres/docker-compose-postgres.yml> |
| PyIceberg 0.12.0 Python requirement | `>=3.10` | <https://pypi.org/project/pyiceberg/0.12.0/> |
| JupyterLab 4.6.4 Python requirement | `>=3.10` | <https://pypi.org/project/jupyterlab/4.6.4/> |
| REST fixture tag for Iceberg 1.11 | Not published; 1.10.1 is the newest versioned tag | <https://hub.docker.com/r/apache/iceberg-rest-fixture/tags> |

Polaris and Nessie do not document tests with Spark 4.1. They are used through the Iceberg
REST protocol with the same Iceberg version they are built against. The smoke tests of
phases 2 and 3 verify the combination.
```

- [ ] **Step 2: Run lint**

Run: `make lint`
Expected: `lint passed` and `no secrets found`.

- [ ] **Step 3: Commit**

```bash
git add VERSIONS.md
git commit -m "docs: add pinned versions with sources"
```

---

## Stage 1 → Stage 2 hand-over (user actions, not a subagent task)

After the Stage 1 PR is merged:

1. The user runs `aws/setup.sh` in CloudShell (see `aws/README-aws.md`).
2. On the VM: `git clone git@github.com:sramazzina/iceberg-platform-poc.git`, `cd iceberg-platform-poc`.
3. On the VM: `cp .env.example .env`, then fill `S3_BUCKET`, `AWS_REGION`, `POLARIS_ROLE_ARN`, `POLARIS_EXTERNAL_ID` from the `setup.sh` output, replace every `change-me`, and set `LAB_UID` to the output of `id -u`.
4. On the VM: run the checks in `aws/README-aws.md` section "Check from the VM".
5. On the VM: start Claude Code in the repository and continue with Task 7.

---

## Task 7: Postgres service with the `polaris` and `nessie` databases (on the VM)

**Files:**
- Create: `postgres/init/01-create-databases.sh`
- Create: `docker-compose.yml`
- Test: `tests/postgres-init.sh`

- [ ] **Step 1: Write the failing test**

`tests/postgres-init.sh`:

```bash
#!/usr/bin/env bash
# Checks that Postgres has the polaris and nessie databases, their owners,
# and the schema that Polaris expects.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

psql_super() { docker compose exec -T postgres psql -U postgres -tAc "$1"; }

echo "postgres"
dbs=$(psql_super "SELECT string_agg(datname || ':' || pg_get_userbyid(datdba), ',' ORDER BY datname) FROM pg_database WHERE datname IN ('polaris', 'nessie')")
assert_eq "$dbs" "nessie:nessie,polaris:polaris" "databases polaris and nessie with their own owners"
schema=$(docker compose exec -T postgres psql -U postgres -d polaris -tAc \
  "SELECT schema_owner FROM information_schema.schemata WHERE schema_name = 'polaris_schema'")
assert_eq "$schema" "polaris" "schema polaris_schema owned by polaris"
for user in polaris nessie; do
  # Inside the container: PGPASSWORD="$POLARIS_DB_PASSWORD" (or NESSIE_...).
  out=$(docker compose exec -T postgres sh -c \
    "PGPASSWORD=\"\$${user^^}_DB_PASSWORD\" psql -h 127.0.0.1 -U $user -d $user -tAc 'SELECT 1'")
  assert_eq "$out" "1" "user $user logs in with its password"
done

finish
```

Run: `chmod +x tests/postgres-init.sh`

- [ ] **Step 2: Write `docker-compose.yml` with the Postgres service**

```yaml
name: iceberg-lab

services:
  postgres:
    image: ${POSTGRES_IMAGE}
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POLARIS_DB_PASSWORD: ${POLARIS_DB_PASSWORD}
      NESSIE_DB_PASSWORD: ${NESSIE_DB_PASSWORD}
    volumes:
      # Postgres 18 images keep data under /var/lib/postgresql/<major>/docker.
      - pgdata:/var/lib/postgresql
      - ./postgres/init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 30

volumes:
  pgdata:
```

Run: `mkdir -p postgres/init` (otherwise Docker creates the bind-mount folder owned by root).

- [ ] **Step 3: Start Postgres and run the test to verify it fails**

Run:
```bash
docker compose up -d --wait postgres
tests/postgres-init.sh
```
Expected: FAIL on `databases polaris and nessie with their own owners` (no init script yet).

- [ ] **Step 4: Write the init script**

`postgres/init/01-create-databases.sh`:

```bash
#!/usr/bin/env bash
# Creates the polaris and nessie databases, each with its own owner, and the
# schema Polaris expects (Polaris does not run CREATE SCHEMA itself).
# Postgres runs this script once, when the data volume is empty.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
  -v polaris_pw="$POLARIS_DB_PASSWORD" -v nessie_pw="$NESSIE_DB_PASSWORD" <<'SQL'
CREATE USER polaris WITH PASSWORD :'polaris_pw';
CREATE DATABASE polaris OWNER polaris;
CREATE USER nessie WITH PASSWORD :'nessie_pw';
CREATE DATABASE nessie OWNER nessie;
\connect polaris
CREATE SCHEMA polaris_schema AUTHORIZATION polaris;
SQL
```

Run: `chmod +x postgres/init/01-create-databases.sh`

- [ ] **Step 5: Recreate the volume and run the test to verify it passes**

Run:
```bash
docker compose down -v
docker compose up -d --wait postgres
tests/postgres-init.sh
```
Expected: every line `ok`, last line `all assertions passed`.

- [ ] **Step 6: Run lint**

Run: `make lint`
Expected: `lint passed` and `no secrets found`.

- [ ] **Step 7: Commit**

```bash
git add docker-compose.yml postgres/init/01-create-databases.sh tests/postgres-init.sh
git commit -m "feat(postgres): add Postgres with polaris and nessie databases"
```

---

## Task 8: Spark image (on the VM)

**Files:**
- Create: `spark/Dockerfile`
- Create: `spark/requirements.txt`
- Create: `spark/entrypoint.sh`
- Create: `spark/conf/spark-defaults.conf`
- Create: `scenarios/.gitkeep`
- Modify: `docker-compose.yml`
- Test: `tests/spark-image.sh`

- [ ] **Step 1: Write the failing test**

`tests/spark-image.sh`:

```bash
#!/usr/bin/env bash
# Checks the content of the spark image: Iceberg jars, AWS CLI, Python packages,
# Spark SQL with the Iceberg extensions.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
set -a; source .env; set +a

run() { docker compose run --rm --no-deps -T spark "$@" 2>&1; }

echo "spark image"
jars=$(run bash -c 'ls "$SPARK_HOME/jars"')
assert_contains "$jars" "$ICEBERG_SPARK_RUNTIME_ARTIFACT-$ICEBERG_VERSION.jar" "Iceberg Spark runtime"
assert_contains "$jars" "iceberg-aws-bundle-$ICEBERG_VERSION.jar" "Iceberg AWS bundle"
assert_contains "$(run aws --version)" "aws-cli/$AWSCLI_VERSION" "AWS CLI pinned version"
py=$(run python3 -c 'import pyspark, pyiceberg, pandas, jupyterlab, requests; print(pyspark.__version__, pyiceberg.__version__)')
assert_contains "$py" "4.1.3 0.12.0" "PySpark and PyIceberg import"
sql=$(run spark-sql -e "SELECT 41 + 1 AS answer")
assert_contains "$sql" "42" "spark-sql runs"
ext=$(run spark-sql -e "SET spark.sql.extensions")
assert_contains "$ext" "IcebergSparkSessionExtensions" "Iceberg extensions configured"
uid=$(run id -u)
assert_eq "$(tail -n1 <<<"$uid")" "$LAB_UID" "runs as LAB_UID"

finish
```

Run: `chmod +x tests/spark-image.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/spark-image.sh`
Expected: FAIL — `no such service: spark`.

- [ ] **Step 3: Write `spark/requirements.txt`**

```text
jupyterlab==4.6.4
pyiceberg[pyarrow,pandas]==0.12.0
pandas==2.3.3
pyarrow==25.0.1
requests==2.34.2
```

- [ ] **Step 4: Write `spark/conf/spark-defaults.conf`**

```text
# Spark defaults for the lab. Catalog blocks are added in phases 2-4.
spark.sql.extensions    org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
spark.driver.memory     4g
```

- [ ] **Step 5: Write `spark/entrypoint.sh`**

```bash
#!/usr/bin/env bash
# Starts JupyterLab. When arguments are given, runs them instead (for example spark-sql).
set -euo pipefail

if (($# > 0)); then
  exec "$@"
fi

exec jupyter lab --ip=0.0.0.0 --port=8888 --no-browser \
  --ServerApp.token="${JUPYTER_TOKEN:?set JUPYTER_TOKEN in .env}" \
  --ServerApp.root_dir=/workspace
```

Run: `chmod +x spark/entrypoint.sh`

- [ ] **Step 6: Write `spark/Dockerfile`**

```dockerfile
# Spark with Apache Iceberg, the AWS CLI and JupyterLab.
# Every version comes from .env through build arguments (see VERSIONS.md).
ARG SPARK_BASE_IMAGE
FROM ${SPARK_BASE_IMAGE}

ARG ICEBERG_VERSION
ARG ICEBERG_SPARK_RUNTIME_ARTIFACT
ARG ICEBERG_SPARK_RUNTIME_SHA1
ARG ICEBERG_AWS_BUNDLE_SHA1
ARG AWSCLI_VERSION
ARG LAB_UID=1000

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl unzip \
 && rm -rf /var/lib/apt/lists/*

# Iceberg jars from Maven Central, checked against the pinned SHA-1.
RUN set -eux; \
    base=https://repo1.maven.org/maven2/org/apache/iceberg; \
    runtime="${ICEBERG_SPARK_RUNTIME_ARTIFACT}-${ICEBERG_VERSION}.jar"; \
    bundle="iceberg-aws-bundle-${ICEBERG_VERSION}.jar"; \
    curl -fsSLo "$SPARK_HOME/jars/$runtime" "$base/${ICEBERG_SPARK_RUNTIME_ARTIFACT}/${ICEBERG_VERSION}/$runtime"; \
    echo "${ICEBERG_SPARK_RUNTIME_SHA1}  $SPARK_HOME/jars/$runtime" | sha1sum -c -; \
    curl -fsSLo "$SPARK_HOME/jars/$bundle" "$base/iceberg-aws-bundle/${ICEBERG_VERSION}/$bundle"; \
    echo "${ICEBERG_AWS_BUNDLE_SHA1}  $SPARK_HOME/jars/$bundle" | sha1sum -c -

# AWS CLI v2, pinned version.
RUN set -eux; \
    curl -fsSLo /tmp/awscli.zip "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m)-${AWSCLI_VERSION}.zip"; \
    unzip -q /tmp/awscli.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscli.zip; \
    aws --version

COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt && rm /tmp/requirements.txt

# Stable path to the py4j archive bundled with Spark, so the Jupyter kernel can import pyspark.
RUN ln -s "$(ls "$SPARK_HOME"/python/lib/py4j-*-src.zip)" "$SPARK_HOME/python/lib/py4j-src.zip"
ENV PYTHONPATH=/opt/spark/python:/opt/spark/python/lib/py4j-src.zip \
    PATH=/opt/spark/bin:$PATH \
    HOME=/workspace

# The spark user gets the host UID, so files saved in bind mounts stay editable on the host.
RUN groupmod -g "$LAB_UID" spark \
 && usermod -u "$LAB_UID" -d /workspace spark \
 && mkdir -p /workspace \
 && chown -R spark:spark /workspace "$SPARK_HOME"

COPY conf/spark-defaults.conf /opt/spark/conf/spark-defaults.conf
COPY entrypoint.sh /usr/local/bin/lab-entrypoint.sh

USER spark
WORKDIR /workspace
EXPOSE 8888 4040
ENTRYPOINT ["/usr/local/bin/lab-entrypoint.sh"]
```

- [ ] **Step 7: Add the `spark` service to `docker-compose.yml`**

Insert this block under `services:`, after the `postgres` service:

```yaml
  spark:
    build:
      context: ./spark
      args:
        SPARK_BASE_IMAGE: ${SPARK_BASE_IMAGE}
        ICEBERG_VERSION: ${ICEBERG_VERSION}
        ICEBERG_SPARK_RUNTIME_ARTIFACT: ${ICEBERG_SPARK_RUNTIME_ARTIFACT}
        ICEBERG_SPARK_RUNTIME_SHA1: ${ICEBERG_SPARK_RUNTIME_SHA1}
        ICEBERG_AWS_BUNDLE_SHA1: ${ICEBERG_AWS_BUNDLE_SHA1}
        AWSCLI_VERSION: ${AWSCLI_VERSION}
        LAB_UID: ${LAB_UID}
    image: iceberg-lab-spark:${ICEBERG_VERSION}
    environment:
      S3_BUCKET: ${S3_BUCKET}
      AWS_REGION: ${AWS_REGION}
      S3_ENDPOINT: ${S3_ENDPOINT:-}
      S3_PATH_STYLE_ACCESS: ${S3_PATH_STYLE_ACCESS:-false}
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:-}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:-}
      JUPYTER_TOKEN: ${JUPYTER_TOKEN}
    ports:
      - "127.0.0.1:8888:8888"
      - "127.0.0.1:4040:4040"
    volumes:
      - ./scenarios:/workspace/scenarios
      - ./tests:/workspace/tests:ro
```

Run: `mkdir -p scenarios && touch scenarios/.gitkeep`

- [ ] **Step 8: Build the image and run the test to verify it passes**

Run:
```bash
docker compose build spark
tests/spark-image.sh
```
Expected: the build prints two `OK` lines from `sha1sum -c` and `aws-cli/2.39.0`; the test prints every line `ok`, last line `all assertions passed`.

If `pip3 install` fails on a dependency conflict, report the pip error to the controller; do not change versions without approval (versions are a user decision recorded in `VERSIONS.md`).

- [ ] **Step 9: Run lint**

Run: `make lint`
Expected: `lint passed` and `no secrets found`.

- [ ] **Step 10: Commit**

```bash
git add spark tests/spark-image.sh scenarios/.gitkeep docker-compose.yml
git commit -m "feat(spark): add Spark image with Iceberg, AWS CLI and JupyterLab"
```

---

## Task 9: Phase 1 acceptance test and stack targets (on the VM)

**Files:**
- Create: `tests/s3_access.py`
- Create: `tests/s3-access.sh`
- Modify: `Makefile`

- [ ] **Step 1: Write the Spark-side test program**

`tests/s3_access.py`:

```python
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
```

- [ ] **Step 2: Write the shell wrapper**

`tests/s3-access.sh`:

```bash
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
```

With `set -o pipefail`, the script exits non-zero when `spark-submit` fails (a `FAIL` line makes `s3_access.py` exit 1).

Run: `chmod +x tests/s3-access.sh`

- [ ] **Step 3: Add the stack targets to the Makefile**

Replace the `Makefile` content with:

```make
.PHONY: lint test-aws up down reset logs smoke-test

lint:
	tests/lint.sh
	tests/check-no-secrets.sh

test-aws:
	tests/test-iam-policies.sh
	tests/test-aws-setup.sh
	tests/test-aws-teardown.sh

up:
	docker compose up -d --build --wait

down:
	docker compose down

reset:
	docker compose down -v

logs:
	docker compose logs -f --tail=200

smoke-test:
	tests/postgres-init.sh
	tests/s3-access.sh
```

- [ ] **Step 4: Start the stack and run the acceptance test**

Run:
```bash
make up
make smoke-test
```
Expected: `all assertions passed` from `postgres-init.sh`; then `ok - aws s3 ls on the bucket root`, `ok - write and read back s3://…/rest/_smoke/…`, `ok - delete …`, `ok - write to s3://…/polaris/_smoke/… is denied`; exit code 0.

If `aws s3 ls` fails with `Unable to locate credentials`, check the hop limit: `aws ec2 describe-instances --instance-ids <id> --query 'Reservations[0].Instances[0].MetadataOptions'` must show `"HttpPutResponseHopLimit": 2`. Report to the controller; do not change AWS resources.

- [ ] **Step 5: Verify that a failing check fails the target**

Run: `docker compose stop spark; make smoke-test; echo "exit=$?"; docker compose start spark`
Expected: `exit=2` (make reports the failed recipe).

- [ ] **Step 6: Run lint**

Run: `make lint`
Expected: `lint passed` and `no secrets found`.

- [ ] **Step 7: Commit**

```bash
git add tests/s3_access.py tests/s3-access.sh Makefile
git commit -m "test: add phase 1 S3 access acceptance test and stack targets"
```

---

## Out of scope for this plan

Phases 2-6 (Polaris, Nessie, baseline, scenarios, evaluation and README) get one plan each,
written on the VM after Phase 1 passes. They will add: the `sql-polaris`, `sql-nessie`,
`sql-rest`, `up-baseline` and `scenarios` Makefile targets; the rendering of
`spark-defaults.conf` from a template in `entrypoint.sh`; `tests/catalog-smoke.sh`.
