#!/bin/sh
# Idempotent RustFS setup (spec 2026-10-29-rustfs-onprem, section 7): the bucket S3_BUCKET,
# the users polaris and lab, and their policies. Runs in the rc image: POSIX sh, no bash.
set -eu

fail() { echo "rustfs-setup: $*" >&2; exit 1; }

for name in S3_BUCKET RUSTFS_ROOT_ACCESS_KEY RUSTFS_ROOT_SECRET_KEY RUSTFS_POLARIS_ACCESS_KEY \
  RUSTFS_POLARIS_SECRET_KEY RUSTFS_LAB_ACCESS_KEY RUSTFS_LAB_SECRET_KEY; do
  eval "value=\${$name:-}"
  [ -n "$value" ] || fail "$name is empty: set it in .env (see .env.example)"
done

rc alias set lab http://rustfs:9000 "$RUSTFS_ROOT_ACCESS_KEY" "$RUSTFS_ROOT_SECRET_KEY" >/dev/null \
  || fail "cannot connect to rustfs with the root keys"

if rc ls "lab/$S3_BUCKET" >/dev/null 2>&1; then
  echo "rustfs-setup: bucket $S3_BUCKET already present"
else
  rc mb "lab/$S3_BUCKET" >/dev/null || fail "cannot create the bucket $S3_BUCKET"
  echo "rustfs-setup: bucket $S3_BUCKET created"
fi

# user NAME ACCESS_KEY SECRET_KEY: sets the policy lab-NAME from /setup/policy-NAME.json and
# the user ACCESS_KEY with this policy. In RustFS the access key is the user name.
user() {
  policy=/tmp/policy-$1.json
  sed "s/\${S3_BUCKET}/$S3_BUCKET/g" "/setup/policy-$1.json" >"$policy"
  rc admin policy create lab/ "lab-$1" "$policy" >/dev/null || fail "policy lab-$1"
  rc admin user add lab/ "$2" "$3" >/dev/null || fail "user $1"
  rc admin policy attach lab/ "lab-$1" --user "$2" >/dev/null || fail "policy lab-$1 for the user $1"
  echo "rustfs-setup: user $1 with policy lab-$1 set"
}
user polaris "$RUSTFS_POLARIS_ACCESS_KEY" "$RUSTFS_POLARIS_SECRET_KEY"
user lab "$RUSTFS_LAB_ACCESS_KEY" "$RUSTFS_LAB_SECRET_KEY"

echo "rustfs-setup: done"
