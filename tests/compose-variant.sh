#!/usr/bin/env bash
# Static checks of the Compose configuration of the AWS stack and of the RustFS variant
# (spec 2026-10-29-rustfs-onprem, sections 6 and 8). No container runs.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

# Always the template: the result must not depend on the values of the user's .env.
# Shell variables still override it (Compose rule).
env_file=.env.example

# config FILES: the rendered configuration (JSON) for COMPOSE_FILE=FILES, every profile on.
config() {
  COMPOSE_FILE="$1" COMPOSE_PROFILES='*' docker compose --env-file "$env_file" \
    config --format json || echo '{}'
}
# q JSON FILTER: the jq result as raw text.
q() { jq -r "$2" <<<"$1" 2>/dev/null || echo "jq failed"; }

# src JSON SERVICE TARGET: the source of the mount of SERVICE on the container path TARGET.
src() {
  jq -r --arg s "$2" --arg t "$3" \
    '.services[$s].volumes[]? | select(.target == $t) | .source' <<<"$1" 2>/dev/null || echo "jq failed"
}

aws=$(config docker-compose.yml)
rustfs=$(config docker-compose.yml:docker-compose.rustfs.yml)

echo "compose variant: AWS stack"
assert_eq "$(q "$aws" '.services | has("rustfs")')" "false" "no rustfs service"
assert_eq "$(src "$aws" postgres /var/lib/postgresql)" "pgdata" "postgres data on the volume pgdata"
assert_eq "$(src "$aws" rest-fixture /home/iceberg)" "rest-fixture-data" "rest catalog on the volume rest-fixture-data"

echo "compose variant: RustFS"
assert_eq "$(q "$rustfs" '.services.rustfs.image')" "$(sed -n 's/^RUSTFS_IMAGE=//p' .env.example)" "rustfs image pinned in .env.example"
assert_eq "$(q "$rustfs" '.services.rustfs.environment.RUSTFS_VOLUMES')" "/data" "rustfs data in /data"
assert_eq "$(q "$rustfs" '.services.rustfs.volumes[] | select(.target == "/data") | .type')" "bind" "rustfs data on a bind mount"
assert_eq "$(q "$rustfs" '[.services.rustfs.ports[] | "\(.host_ip):\(.published)->\(.target)"] | join(",")')" \
  "127.0.0.1:9100->9000,127.0.0.1:9101->9001" "rustfs ports on 127.0.0.1:9100 and 9101"
assert_eq "$(src "$rustfs" postgres /var/lib/postgresql)" "pgdata-rustfs" "postgres data on the volume pgdata-rustfs"
assert_eq "$(src "$rustfs" rest-fixture /home/iceberg)" "rest-fixture-data-rustfs" "rest catalog on the volume rest-fixture-data-rustfs"
assert_eq "$(src "$rustfs" postgres /docker-entrypoint-initdb.d | sed 's#.*/##')" "init" "postgres init scripts kept"
lab_uid=${LAB_UID:-$(sed -n 's/^LAB_UID=//p' "$env_file")}; lab_uid=${lab_uid:-1000}
assert_eq "$(q "$rustfs" '.services.rustfs.user')" "$lab_uid" "rustfs runs with LAB_UID"

assert_eq "$(q "$rustfs" '.services["rustfs-setup"].image')" "$(sed -n 's/^RUSTFS_RC_IMAGE=//p' .env.example)" "rustfs-setup image pinned in .env.example"
assert_eq "$(q "$rustfs" '.services["rustfs-setup"].depends_on.rustfs.condition')" "service_healthy" "rustfs-setup waits for a healthy rustfs"
assert_eq "$(src "$rustfs" rustfs-setup /setup | sed 's#.*/rustfs/#rustfs/#')" "rustfs/setup" "rustfs-setup mounts rustfs/setup"

finish
