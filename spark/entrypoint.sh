#!/usr/bin/env bash
# Starts JupyterLab. When arguments are given, runs them instead (for example spark-sql).
set -euo pipefail

if (($# > 0)); then
  exec "$@"
fi

exec jupyter lab --ip=0.0.0.0 --port=8888 --no-browser \
  --ServerApp.token="${JUPYTER_TOKEN:?set JUPYTER_TOKEN in .env}" \
  --ServerApp.root_dir=/workspace
