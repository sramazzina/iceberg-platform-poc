#!/usr/bin/env bash
# RustFS setup test (spec 2026-10-29-rustfs-onprem, sections 7 and 8): rustfs-setup is
# idempotent. Run it on the RustFS variant, after `make up`.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

echo "rustfs setup"
status=0
out=$(docker compose run --rm -T rustfs-setup 2>&1) || status=$?
assert_eq "$status" "0" "a second run of rustfs-setup exits 0"
assert_contains "$out" "already present" "the bucket is already present"
assert_contains "$out" "user polaris with policy lab-polaris set" "user polaris set"
assert_contains "$out" "user lab with policy lab-lab set" "user lab set"
assert_contains "$out" "rustfs-setup: done" "rustfs-setup completes"
if ((status != 0)); then sed 's/^/    /' <<<"$out" | tail -n 20; fi

finish
