#!/usr/bin/env bash
# Creates the polaris and nessie databases, each with its own owner, and the
# schema Polaris expects (Polaris does not run CREATE SCHEMA itself).
# Postgres runs this script once, when the data volume is empty.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
  -v polaris_pw="$POLARIS_DB_PASSWORD" -v nessie_pw="$NESSIE_DB_PASSWORD" <<'SQL'
CREATE USER polaris WITH PASSWORD :'polaris_pw';
CREATE DATABASE polaris OWNER polaris;
CREATE USER nessie WITH PASSWORD :'nessie_pw';
CREATE DATABASE nessie OWNER nessie;
\connect polaris
CREATE SCHEMA polaris_schema AUTHORIZATION polaris;
SQL
