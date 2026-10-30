#!/usr/bin/env bash
# Checks that the catalogs follow COMPOSE_PROFILES: off by default, on when selected,
# and stopped by `make up` when they are removed from the selection.
# It does not source .env: COMPOSE_PROFILES in the shell overrides the value in .env.
# On exit it runs `make up` again, so the stack returns to the .env selection.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

# The service lists below are the lists of the AWS stack.
if docker compose config --services 2>/dev/null | grep -qx rustfs; then
  echo "catalog selection: skipped on the RustFS variant"
  exit 0
fi
log=$(mktemp)
trap 'rm -f "$log"; make up >/dev/null 2>&1 || echo "  warn - make up with the .env selection failed"' EXIT

services() { COMPOSE_PROFILES="$1" docker compose config --services 2>&1 | sort | paste -sd, -; }
running() { docker compose ps --status running --services 2>/dev/null | sort | paste -sd, -; }

echo "catalog selection"
assert_eq "$(services '')" "postgres,spark" "no catalog when COMPOSE_PROFILES is empty"
assert_eq "$(services nessie)" "nessie,postgres,spark" "COMPOSE_PROFILES=nessie adds nessie"
assert_eq "$(services polaris)" "polaris,polaris-bootstrap,polaris-setup,postgres,spark" "COMPOSE_PROFILES=polaris adds the polaris services"
assert_eq "$(services baseline)" "postgres,rest-fixture,spark" "COMPOSE_PROFILES=baseline adds rest-fixture"
assert_contains "$(command cat .env.example)" $'\nCOMPOSE_PROFILES=\n' ".env.example leaves COMPOSE_PROFILES empty"

COMPOSE_PROFILES= make up >"$log" 2>&1 || { fail "make up with no catalog"; tail -n 20 "$log"; }
assert_eq "$(running)" "postgres,spark" "make up with no catalog stops nessie"
COMPOSE_PROFILES=nessie make up >"$log" 2>&1 || { fail "make up with nessie"; tail -n 20 "$log"; }
assert_eq "$(running)" "nessie,postgres,spark" "make up with nessie starts nessie"

finish
