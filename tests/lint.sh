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
