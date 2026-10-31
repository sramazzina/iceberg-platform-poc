#!/usr/bin/env bash
# Usage: elt/require.sh CATALOG [thrift]
# Stops with a clear message when CATALOG (polaris, nessie or rest) is off, or when
# "thrift" is given and the Spark Thrift Server is off. Runs on the host. A service is on
# when it is in the active Compose configuration (COMPOSE_PROFILES).
set -euo pipefail

catalog=${1:-}
need=${2:-}
case $catalog in
  polaris) service=polaris; profile=polaris ;;
  nessie) service=nessie; profile=nessie ;;
  rest) service=rest-fixture; profile=baseline ;;
  *) echo "set CATALOG=polaris|nessie|rest (got '$catalog')" >&2; exit 2 ;;
esac

services=$(docker compose config --services)
if ! grep -qx "$service" <<<"$services"; then
  echo "catalog $catalog is off: add $profile to COMPOSE_PROFILES, then run make up" >&2
  exit 1
fi
if [[ $need == thrift ]] && ! grep -qx spark-thrift <<<"$services"; then
  echo "the Spark Thrift Server is off: add thrift to COMPOSE_PROFILES, then run make up" >&2
  exit 1
fi
