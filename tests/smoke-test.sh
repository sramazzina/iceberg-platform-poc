#!/usr/bin/env bash
# Runs the acceptance tests of the base stack, then the tests of each catalog that is on
# (a catalog is on when its service is in the active Compose configuration).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

tests/postgres-init.sh
tests/s3-access.sh

services=$(docker compose config --services)
ran=0
for catalog in nessie polaris; do
  if grep -qx "$catalog" <<<"$services"; then
    "tests/$catalog-service.sh"
    tests/catalog-smoke.sh "$catalog"
    ran=1
  fi
done
if ((ran == 0)); then
  echo "no catalog in COMPOSE_PROFILES: only the base tests ran"
fi
