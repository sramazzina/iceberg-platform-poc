#!/usr/bin/env bash
# Runs the acceptance tests of the base stack, then the tests of each catalog that is on
# (a catalog is on when its service is in the active Compose configuration).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

tests/postgres-init.sh
# The RustFS variant: rustfs-setup must be idempotent.
if docker compose config --services | grep -qx rustfs; then tests/rustfs-setup.sh; fi
tests/s3-access.sh
# The Spark Thrift Server (profile thrift).
if docker compose config --services | grep -qx spark-thrift; then tests/thrift-service.sh; fi

services=$(docker compose config --services)
ran=0
# service:catalog for each catalog. For the profile baseline the names differ: service
# rest-fixture, Spark catalog rest. A service test runs when tests/<service>-service.sh exists.
for entry in nessie:nessie polaris:polaris rest-fixture:rest; do
  service=${entry%%:*}
  catalog=${entry#*:}
  if grep -qx "$service" <<<"$services"; then
    if [[ -f tests/$service-service.sh ]]; then "tests/$service-service.sh"; fi
    tests/catalog-smoke.sh "$catalog"
    ran=1
  fi
done
if ((ran == 0)); then
  echo "no catalog in COMPOSE_PROFILES: only the base tests ran"
fi
