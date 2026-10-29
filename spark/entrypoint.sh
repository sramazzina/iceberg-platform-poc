#!/usr/bin/env bash
# Renders the Spark configuration for the catalogs that are on (LAB_CATALOGS, a copy of
# COMPOSE_PROFILES), then starts JupyterLab. When arguments are given, runs them instead
# (for example spark-sql).
set -euo pipefail
source /usr/local/lib/lab/render.sh

templates=/opt/spark/conf-templates
conf=/opt/spark/conf/spark-defaults.conf
secrets=/run/lab-secrets/spark_user.env

IFS=', ' read -ra list <<<"${LAB_CATALOGS:-}"

# The Polaris template needs the spark_user credentials written by polaris-setup.
# Source them only when Polaris is on; do not export them.
for catalog in "${list[@]}"; do
  if [[ $catalog == polaris && -f $secrets ]]; then
    source "$secrets"
  fi
done

# The rendered file can hold the Polaris client secret: keep it private.
umask 077
{
  render_template "$templates/spark-defaults.conf"
  for catalog in "${list[@]}"; do
    if [[ $catalog == '*' ]]; then
      echo "lab-entrypoint: COMPOSE_PROFILES='*' is not supported for Spark; list the catalogs" >&2
    elif [[ -f $templates/catalogs/$catalog.conf ]]; then
      printf '\n'
      render_template "$templates/catalogs/$catalog.conf"
    else
      echo "lab-entrypoint: no Spark catalog for profile '$catalog' (spark/conf/catalogs/$catalog.conf)" >&2
    fi
  done
} >"$conf.new"
mv "$conf.new" "$conf"

if (($# > 0)); then
  exec "$@"
fi

exec jupyter lab --ip=0.0.0.0 --port=8888 --no-browser \
  --ServerApp.token="${JUPYTER_TOKEN:?set JUPYTER_TOKEN in .env}" \
  --ServerApp.root_dir=/workspace
