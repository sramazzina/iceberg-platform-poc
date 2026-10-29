# Iceberg catalog lab — Phase 2 (Polaris) and optional catalogs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every catalog optional (off by default, selected with `COMPOSE_PROFILES` in `.env`), and add Apache Polaris as the Iceberg REST catalog `polaris` with credential vending.

**Architecture:** Each catalog is a Compose profile: `nessie` and `polaris` (`polaris-bootstrap`, `polaris`, `polaris-setup`). `postgres` and `spark` always start. At container start, the Spark entrypoint joins the common configuration and one template per catalog that is on, and replaces the placeholders (the Polaris template gets the `spark_user` credentials that `polaris-setup` writes to `secrets/spark_user.env`). Polaris assumes the role `polaris-s3-access` and vends S3 credentials to Spark; the VM role can only list `polaris/`.

**Tech Stack:** Apache Polaris 1.8.0 (Quarkus, Java 21) with `relational-jdbc` on PostgreSQL 18, Polaris admin tool 1.8.0, `alpine/curl` (POSIX `sh`, `curl`, `sed`), Spark 4.1.3 with the Iceberg 1.11.0 REST client, Docker Compose profiles, Bash, jq on the host.

**Spec:** `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md`, sections 5.0, 5, 5.1, 5.2, 6, 8 (updated on 2026-10-29).

---

## Facts verified on 2026-10-29 (Polaris 1.8.0, on this VM)

Sources: tag `apache-polaris-1.8.0` (`runtime/defaults/src/main/resources/application.properties`,
`site/content/in-dev/unreleased/metastores/relational-jdbc.md`, `admin-tool.md`,
`spec/polaris-management-service.yml`, `FeatureConfiguration.java`), plus throwaway containers
on this VM against real S3.

- Persistence: `POLARIS_PERSISTENCE_TYPE=relational-jdbc` with `QUARKUS_DATASOURCE_JDBC_URL`,
  `QUARKUS_DATASOURCE_USERNAME`, `QUARKUS_DATASOURCE_PASSWORD`. The default `currentSchema` is
  `POLARIS_SCHEMA`, which Postgres folds to `polaris_schema` (created by the Task 7 init script).
- The server does not create its tables. The admin tool does:
  `bootstrap -r POLARIS -c POLARIS,<root id>,<root secret>`. First run: `Realm 'POLARIS'
  successfully bootstrapped.` Second run: `Realm 'POLARIS' is already bootstrapped; skipping.`
  Both exit 0. The image entrypoint is `run-java.sh`, so the Compose `command` is the argument list.
- The default realm is `POLARIS`. Token: `POST /api/catalog/v1/oauth/tokens` with basic auth
  `<id>:<secret>` and `grant_type=client_credentials`, `scope=PRINCIPAL_ROLE:ALL`.
- Management API `http://polaris:8181/api/management/v1`: create returns 201, a duplicate returns
  409. `POST /principals` returns the `clientId` and `clientSecret` once. `POST
  /principals/spark_user/reset` with `{}` (as `root`) returns 200 with new credentials. `rotate`
  as `root` returns 403.
- Polaris calls STS with the AWS default credential chain (the VM instance profile through
  IMDSv2, hop limit 2) and assumes `polaris-s3-access` with the external ID. The region comes from
  `storageConfigInfo.region`.
- Spark `DROP TABLE ... PURGE` deletes the files with the vended credentials, also when the
  catalog property `polaris.config.drop-with-purge.enabled` is false. A REST
  `DELETE ...?purgeRequested=true` gets 403 unless the property is true. The lab uses the Spark
  purge and does not set the property.
- Ports: 8181 (API), 8182 (management, `/q/health/ready`). The image has `curl` and `bash`.
  User `polaris` (UID 10000). With `mem_limit: 1g` and
  `JAVA_OPTS_APPEND=-Xmx384m -XX:MaxDirectMemorySize=128m`, idle use is about 183 MiB, start
  about 15 s.
- `alpine/curl:8.22.0` has `sh`, `sed`, `awk`, `grep`, and no `jq`, `bash` or `python3`.
- Spark catalog without warnings: `type=rest`, `uri=http://polaris:8181/api/catalog`,
  `warehouse=lab_catalog`, `credential=<id>:<secret>`, `scope=PRINCIPAL_ROLE:ALL`,
  `header.X-Iceberg-Access-Delegation=vended-credentials`, `rest.auth.type=oauth2`,
  `oauth2-server-uri=http://polaris:8181/api/catalog/v1/oauth/tokens`.

## Conventions for every task

- All file content, comments, commit messages: English.
- Commit messages: Conventional Commits style, **no `Co-Authored-By` line** and no Claude
  attribution (`CLAUDE.md`).
- Do not push. The controller pushes the batch and opens the PR.
- Never write a real account ID, bucket name, ARN, external ID, password or secret into a
  tracked file. `.env` holds real values: never print it, never commit it.
- `.env` exception: the implementer may set the one line `COMPOSE_PROFILES=...` with `sed`
  (add it at the end when it is missing). This line holds no secret. Never print other lines.
- `secrets/` is git-ignored. Never print `secrets/spark_user.env`.
- Never run `aws/setup.sh` or `aws/teardown.sh`, and never change an AWS resource. The `aws`
  CLI runs only inside the `spark` container, as part of a test.
- The VM role **cannot delete** under `polaris/`. Every Polaris table that a test or an
  experiment creates must be dropped with `DROP TABLE ... PURGE`. If an object is left under
  `polaris/`, report its exact key (bucket redacted as `<bucket>`): the user deletes it from
  CloudShell.
- No `${VAR:?}` in `docker-compose.yml`: `make lint` renders the file against `.env.example`.
- In this shell `cat` is an alias for a missing `bat`: use `command cat` or the Write tool.
- Do not run `make reset` or `docker compose down -v` (they delete the Postgres volume).
- Branch: `phase2-polaris` (already checked out).

## File map

| File | Responsibility | Task |
|---|---|---|
| `docker-compose.yml` | Profiles; `spark` optional dependencies; Polaris services | 13, 14, 15 |
| `.env.example` | `COMPOSE_PROFILES` (empty) | 13 |
| `Makefile` | `up` stops the catalogs that are off; `down`/`reset` for every profile; `sql-polaris`; `smoke-test` | 13, 15 |
| `tests/lint.sh` | Compose check with every profile | 13 |
| `tests/catalog-selection.sh` | The catalogs follow `COMPOSE_PROFILES` | 13, 15 |
| `tests/smoke-test.sh` | Base tests, then the tests of each catalog that is on | 13 |
| `spark/conf/spark-defaults.conf` | Common Spark configuration | 14 |
| `spark/conf/catalogs/nessie.conf` | Spark catalog `nessie` | 14 |
| `spark/conf/catalogs/polaris.conf` | Spark catalog `polaris` (template) | 15 |
| `spark/render.sh` | `render_template` (copy of `aws/lib.sh`) | 14 |
| `spark/entrypoint.sh` | Renders the configuration, then starts JupyterLab or runs a command | 14 |
| `spark/Dockerfile` | Copies the templates and `render.sh` | 14 |
| `tests/spark-config.sh` | Rendered configuration per catalog selection | 14, 15 |
| `polaris/setup/setup.sh` | Idempotent catalog, principal, roles, grants; writes `secrets/spark_user.env` | 15 |
| `tests/polaris-service.sh` | Polaris health, catalog, roles, Spark uses `spark_user` | 15 |
| `tests/catalog-smoke.sh` | `polaris` case with `DROP TABLE ... PURGE` | 16 |
| `NOTES.md`, `README.md`, `docs/HANDOFF.md` | Deviations, findings, status, access table | 17 |

---

## Task 13: Optional catalogs with Compose profiles

**Files:**
- Modify: `docker-compose.yml`
- Modify: `.env.example`
- Modify: `Makefile`
- Modify: `tests/lint.sh`
- Create: `tests/smoke-test.sh`
- Test: `tests/catalog-selection.sh`

- [ ] **Step 1: Write the failing test**

`tests/catalog-selection.sh`:

```bash
#!/usr/bin/env bash
# Checks that the catalogs follow COMPOSE_PROFILES: off by default, on when selected,
# and stopped by `make up` when they are removed from the selection.
# It does not source .env: COMPOSE_PROFILES in the shell overrides the value in .env.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

services() { COMPOSE_PROFILES="$1" docker compose config --services 2>&1 | sort | paste -sd, -; }
running() { docker compose ps --status running --services 2>/dev/null | sort | paste -sd, -; }

echo "catalog selection"
assert_eq "$(services '')" "postgres,spark" "no catalog when COMPOSE_PROFILES is empty"
assert_eq "$(services nessie)" "nessie,postgres,spark" "COMPOSE_PROFILES=nessie adds nessie"
assert_contains "$(command cat .env.example)" $'\nCOMPOSE_PROFILES=\n' ".env.example leaves COMPOSE_PROFILES empty"

COMPOSE_PROFILES= make up >/dev/null 2>&1 || fail "make up with no catalog"
assert_eq "$(running)" "postgres,spark" "make up with no catalog stops nessie"
COMPOSE_PROFILES=nessie make up >/dev/null 2>&1 || fail "make up with nessie"
assert_eq "$(running)" "nessie,postgres,spark" "make up with nessie starts nessie"

finish
```

Run: `chmod +x tests/catalog-selection.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/catalog-selection.sh`
Expected: FAIL on `no catalog when COMPOSE_PROFILES is empty` (got `nessie,postgres,spark`), on
`.env.example leaves COMPOSE_PROFILES empty`, and on `make up with no catalog stops nessie`.

- [ ] **Step 3: Put `nessie` in the profile `nessie`**

In `docker-compose.yml`, in the `nessie` service, add after `image: ${NESSIE_IMAGE}`:

```yaml
    # Catalogs are off by default; COMPOSE_PROFILES in .env selects them (spec section 5.0).
    profiles: [nessie]
```

- [ ] **Step 4: Make the `spark` dependency on `nessie` optional**

In the `spark` service, replace the `depends_on` block with:

```yaml
    depends_on:
      # required: false lets spark start when the catalog is off.
      nessie:
        condition: service_healthy
        required: false
```

- [ ] **Step 5: Add `COMPOSE_PROFILES` to `.env.example`**

Insert before the line `# ---- S3 storage ---...`:

```text
# ---- Catalogs -----------------------------------------------------------------
# Catalogs to start, comma-separated: nessie, polaris. Empty = no catalog (default).
# Compose reads this variable itself. Run `make up` after a change.
COMPOSE_PROFILES=

```

- [ ] **Step 6: Change the Makefile targets**

Replace the targets `up`, `down` and `reset` with the block below, and replace the
`smoke-test` recipe with `tests/smoke-test.sh`:

```make
# Every profile, so that the catalogs that are off are also stopped or removed.
ALL_PROFILES = COMPOSE_PROFILES='*'

up:
	mkdir -p secrets
	@on=$$(docker compose config --services); \
	off=$$($(ALL_PROFILES) docker compose config --services | grep -vxF "$$on" || true); \
	if [ -n "$$off" ]; then $(ALL_PROFILES) docker compose stop $$off; fi
	docker compose up -d --build --wait

down:
	$(ALL_PROFILES) docker compose down

reset:
	$(ALL_PROFILES) docker compose down -v

smoke-test:
	tests/smoke-test.sh
```

`mkdir -p secrets` makes sure that the bind mount of Task 14 is owned by the host user, not by
root.

- [ ] **Step 7: Write `tests/smoke-test.sh`**

```bash
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
```

Run: `chmod +x tests/smoke-test.sh`

- [ ] **Step 8: Check Compose with every profile in `tests/lint.sh`**

Replace the line

```bash
  docker compose --env-file "$env_file" config --quiet || { echo "invalid docker-compose.yml"; status=1; }
```

with

```bash
  COMPOSE_PROFILES='*' docker compose --env-file "$env_file" config --quiet || { echo "invalid docker-compose.yml"; status=1; }
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `tests/catalog-selection.sh`
Expected: every line `ok`, last line `all assertions passed`.

If `COMPOSE_PROFILES= make up` does not override a `COMPOSE_PROFILES` line in `.env`, or if
`COMPOSE_PROFILES='*'` is not accepted by Compose v5, report the exact error to the controller.
If `docker compose up --wait` fails because of a one-shot service, report it too (Task 15 adds
one-shot services).

- [ ] **Step 10: Select Nessie in `.env` and run lint and the smoke test**

Run:
```bash
grep -q '^COMPOSE_PROFILES=' .env && sed -i 's/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=nessie/' .env \
  || printf '\nCOMPOSE_PROFILES=nessie\n' >> .env
make up
make lint
make smoke-test
COMPOSE_PROFILES= tests/smoke-test.sh 2>&1 | tail -n 1
```
Expected: `lint passed`, `no secrets found`; `make smoke-test` runs the Nessie tests and exits 0;
the last command prints `no catalog in COMPOSE_PROFILES: only the base tests ran`.

- [ ] **Step 11: Commit**

```bash
git add docker-compose.yml .env.example Makefile tests/lint.sh tests/smoke-test.sh tests/catalog-selection.sh
git commit -m "feat: make the catalogs optional with Compose profiles"
```

---

## Task 14: Spark configuration rendered per catalog

**Files:**
- Modify: `spark/conf/spark-defaults.conf`
- Create: `spark/conf/catalogs/nessie.conf`
- Create: `spark/render.sh`
- Modify: `spark/entrypoint.sh`
- Modify: `spark/Dockerfile`
- Modify: `docker-compose.yml`
- Test: `tests/spark-config.sh`

- [ ] **Step 1: Write the failing test**

`tests/spark-config.sh`:

```bash
#!/usr/bin/env bash
# Checks the Spark configuration that the entrypoint renders for a catalog selection.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

# conf CATALOGS: the rendered spark-defaults.conf for LAB_CATALOGS=CATALOGS.
conf() {
  docker compose run --rm --no-deps -T -e LAB_CATALOGS="$1" spark \
    cat /opt/spark/conf/spark-defaults.conf 2>&1 || echo "command failed"
}

echo "spark configuration"
none=$(conf "")
assert_contains "$none" "IcebergSparkSessionExtensions" "common part with no catalog"
assert_not_contains "$none" "spark.sql.catalog.nessie" "no nessie block with no catalog"

nessie=$(conf nessie)
assert_contains "$nessie" "spark.sql.catalog.nessie.uri    http://nessie:19120/iceberg/main" "nessie block with nessie"
assert_contains "$nessie" "IcebergSparkSessionExtensions" "common part with nessie"

unknown=$(conf baseline)
assert_not_contains "$unknown" "command failed" "a profile without a template is skipped"

finish
```

Run: `chmod +x tests/spark-config.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/spark-config.sh`
Expected: FAIL on `no nessie block with no catalog` (the current image always has the block).

- [ ] **Step 3: Move the Nessie block to its own template**

Replace `spark/conf/spark-defaults.conf` with:

```text
# Spark defaults for the lab: the common part. The entrypoint appends the template of
# each catalog that is on (spark/conf/catalogs/<catalog>.conf).
spark.sql.extensions    org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
spark.driver.memory     4g
# No Derby metastore_db: two spark-sql sessions must not collide.
spark.sql.catalogImplementation    in-memory
```

Create `spark/conf/catalogs/nessie.conf`:

```text
# Catalog nessie: Nessie Iceberg REST endpoint, branch main. Spark writes the data files
# with the VM instance profile (Nessie request signing is disabled).
spark.sql.catalog.nessie        org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.nessie.type   rest
spark.sql.catalog.nessie.uri    http://nessie:19120/iceberg/main
```

- [ ] **Step 4: Write `spark/render.sh`**

```bash
# render_template for the spark image. Copy of aws/lib.sh, because the image build
# context is spark/. Source this file; do not run it.

# render_template FILE
# Prints FILE with every ${NAME} placeholder replaced by the value of the shell
# variable NAME. Returns 1 when a placeholder has no value.
render_template() {
  local content name
  content=$(<"$1")
  while [[ $content =~ \$\{([A-Z_][A-Z0-9_]*)\} ]]; do
    name=${BASH_REMATCH[1]}
    if [[ -z ${!name:-} ]]; then
      echo "render_template: variable $name is not set (in $1)" >&2
      return 1
    fi
    if [[ ${!name} == *'${'* ]]; then
      echo "render_template: value of $name contains '\${' (in $1)" >&2
      return 1
    fi
    content=${content//"\${$name}"/"${!name}"}
  done
  printf '%s\n' "$content"
}
```

- [ ] **Step 5: Render the configuration in `spark/entrypoint.sh`**

Replace `spark/entrypoint.sh` with:

```bash
#!/usr/bin/env bash
# Renders the Spark configuration for the catalogs that are on (LAB_CATALOGS, a copy of
# COMPOSE_PROFILES), then starts JupyterLab. When arguments are given, runs them instead
# (for example spark-sql).
set -euo pipefail
source /usr/local/lib/lab/render.sh

templates=/opt/spark/conf-templates
conf=/opt/spark/conf/spark-defaults.conf
secrets=/run/lab-secrets/spark_user.env

# The Polaris template needs the spark_user credentials written by polaris-setup.
if [[ -f $secrets ]]; then
  set -a; source "$secrets"; set +a
fi

catalogs=${LAB_CATALOGS:-}
{
  render_template "$templates/spark-defaults.conf"
  for catalog in ${catalogs//,/ }; do
    if [[ -f $templates/catalogs/$catalog.conf ]]; then
      printf '\n'
      render_template "$templates/catalogs/$catalog.conf"
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
```

An unset or empty `LAB_CATALOGS` gives the common part only. If a placeholder has no value, `render_template` prints the variable name and the container stops
with exit code 1, before Spark reads a half-written file.

- [ ] **Step 6: Copy the templates and `render.sh` in `spark/Dockerfile`**

Replace the line

```dockerfile
COPY --chown=spark:spark conf/spark-defaults.conf /opt/spark/conf/spark-defaults.conf
```

with

```dockerfile
# Configuration templates; the entrypoint renders /opt/spark/conf/spark-defaults.conf at start.
COPY conf/ /opt/spark/conf-templates/
COPY render.sh /usr/local/lib/lab/render.sh
```

`/opt/spark/conf` stays owned by `spark` (the `chown` in the user-change step), so the
entrypoint can write the rendered file.

- [ ] **Step 7: Give `spark` the catalog selection and the secrets folder**

In `docker-compose.yml`, in the `spark` service:

1. Add to `environment`:

```yaml
      # The catalogs that are on; the entrypoint renders their Spark configuration.
      LAB_CATALOGS: ${COMPOSE_PROFILES:-}
```

2. Add to `volumes`:

```yaml
      - ./secrets:/run/lab-secrets:ro
```

- [ ] **Step 8: Rebuild Spark and run the test to verify it passes**

Run:
```bash
docker compose build spark
tests/spark-config.sh
```
Expected: every line `ok`, last line `all assertions passed`.

- [ ] **Step 9: Run lint, the image test and the smoke test**

Run: `make up && make lint && tests/spark-image.sh && make smoke-test`
Expected: all tests pass (with `COMPOSE_PROFILES=nessie` in `.env`), exit code 0.

- [ ] **Step 10: Commit**

```bash
git add spark docker-compose.yml tests/spark-config.sh
git commit -m "feat(spark): render the Spark configuration for the catalogs that are on"
```

---

## Task 15: Polaris services and setup

**Files:**
- Modify: `docker-compose.yml`
- Create: `polaris/setup/setup.sh`
- Create: `spark/conf/catalogs/polaris.conf`
- Modify: `Makefile`
- Modify: `tests/catalog-selection.sh`
- Modify: `tests/spark-config.sh`
- Test: `tests/polaris-service.sh`

- [ ] **Step 1: Write the failing test**

`tests/polaris-service.sh`:

```bash
#!/usr/bin/env bash
# Checks the polaris services: readiness, catalog lab_catalog, roles and grants,
# the spark_user credentials file, and that Spark uses spark_user, never root.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
set -a; source .env; set +a

# curl runs inside the polaris container, so the test does not depend on the published ports.
# api PATH: GET on the management API as root. The root credentials stay in the container env.
api() {
  docker compose exec -T -e POLARIS_ROOT_CLIENT_ID -e POLARIS_ROOT_CLIENT_SECRET polaris bash -c '
    token=$(curl -fsS -X POST http://127.0.0.1:8181/api/catalog/v1/oauth/tokens \
      --user "$POLARIS_ROOT_CLIENT_ID:$POLARIS_ROOT_CLIENT_SECRET" \
      -d grant_type=client_credentials -d scope=PRINCIPAL_ROLE:ALL \
      | sed -n "s/.*\"access_token\":\"\([^\"]*\)\".*/\1/p")
    curl -fsS -H "Authorization: Bearer $token" "http://127.0.0.1:8181/api/management/v1$1"' _ "$1" \
    2>&1 || echo "request failed: $1"
}

echo "polaris"
ready=$(docker compose exec -T polaris curl -fsS http://127.0.0.1:8182/q/health/ready 2>&1 | jq -r .status 2>&1 || true)
assert_eq "$ready" "UP" "readiness check is UP"

catalog=$(api /catalogs/lab_catalog | jq -r '.storageConfigInfo.storageType + " " + .properties["default-base-location"]' 2>&1 || true)
assert_eq "$catalog" "S3 s3://$S3_BUCKET/polaris/" "catalog lab_catalog on S3 with base location polaris/"

grants=$(api /catalogs/lab_catalog/catalog-roles/lab_admin/grants | jq -r '[.grants[].privilege] | join(",")' 2>&1 || true)
assert_contains "$grants" "CATALOG_MANAGE_CONTENT" "catalog role lab_admin can manage content"

roles=$(api /principal-roles/spark_role/catalog-roles/lab_catalog | jq -r '[.roles[].name] | join(",")' 2>&1 || true)
assert_eq "$roles" "lab_admin" "principal role spark_role has lab_admin"

assert_eq "$(stat -c %a secrets/spark_user.env 2>&1 || true)" "600" "secrets/spark_user.env exists, mode 600"

client=$(docker compose exec -T spark sh -c \
  "sed -n 's/^spark.sql.catalog.polaris.credential *\([^:]*\):.*/\1/p' /opt/spark/conf/spark-defaults.conf" 2>&1 || true)
assert_not_contains "$client" "$POLARIS_ROOT_CLIENT_ID" "Spark does not use the root credentials"
assert_eq "$(grep -c . <<<"$client")" "1" "Spark has one polaris credential"

rerun=$(docker compose run --rm --no-deps polaris-setup 2>&1 || echo "polaris-setup failed")
assert_contains "$rerun" "credentials file kept" "a second polaris-setup run keeps the credentials"
assert_not_contains "$rerun" "polaris-setup failed" "a second polaris-setup run succeeds"

finish
```

Run: `chmod +x tests/polaris-service.sh`

Note for the reviewer: `assert_not_contains "$client" "$POLARIS_ROOT_CLIENT_ID"` prints the root
client ID only on failure. A client ID is an identifier, not a secret.

Two points were not verified before this plan. Check them in Step 9 and report what you change:
- `docker compose exec -e NAME` (without `=value`) must pass the host value of `NAME`. If it does
  not, use `-e NAME="$NAME"`.
- The JSON shape of the grants answer (`.grants[].privilege`) and of the catalog roles answer
  (`.roles[].name`). If the shape differs, change only the `jq` paths.

- [ ] **Step 2: Run the test to verify it fails**

Run: `COMPOSE_PROFILES=polaris tests/polaris-service.sh`
Expected: FAIL on every check (`no such service: polaris` inside the FAIL messages).

- [ ] **Step 3: Write `polaris/setup/setup.sh`**

```sh
#!/bin/sh
# Idempotent Polaris setup (spec section 5.1): catalog lab_catalog, principal spark_user,
# principal role spark_role, catalog role lab_admin, and the grants. Writes the spark_user
# credentials to /secrets/spark_user.env. POSIX sh: the image has no bash and no jq, so the
# JSON answers are read with sed.
set -eu

API=http://polaris:8181
MGMT=$API/api/management/v1
OUT=/secrets/spark_user.env
ANSWER=/tmp/polaris-answer

fail() { echo "polaris-setup: $*" >&2; exit 1; }

# field NAME: prints the string value of the JSON field NAME in $ANSWER.
field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p" "$ANSWER"; }

curl -fsS -o "$ANSWER" -X POST "$API/api/catalog/v1/oauth/tokens" \
  --user "$POLARIS_ROOT_CLIENT_ID:$POLARIS_ROOT_CLIENT_SECRET" \
  -d grant_type=client_credentials -d scope=PRINCIPAL_ROLE:ALL || fail "no root token"
token=$(field access_token)
[ -n "$token" ] || fail "no access_token in the token answer"

# call METHOD PATH BODY: prints the HTTP code; the answer goes to $ANSWER.
call() {
  curl -sS -o "$ANSWER" -w '%{http_code}' -X "$1" \
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
    "$MGMT$2" -d "$3"
}

# create WHAT METHOD PATH BODY: HTTP 2xx = created, 409 = already present.
create() {
  what=$1; shift
  code=$(call "$@")
  case $code in
    2??) echo "polaris-setup: $what created" ;;
    409) echo "polaris-setup: $what already present" ;;
    *) fail "$what: HTTP $code: $(command cat "$ANSWER")" ;;
  esac
}

location="s3://$S3_BUCKET/polaris/"
# S3-compatible storage on-premise: endpoint and path-style access (not tested on AWS).
extra=""
if [ -n "${S3_ENDPOINT:-}" ]; then
  extra=",\"endpoint\":\"$S3_ENDPOINT\",\"pathStyleAccess\":${S3_PATH_STYLE_ACCESS:-false}"
fi
create "catalog lab_catalog" POST /catalogs "{\"catalog\":{\"name\":\"lab_catalog\",\"type\":\"INTERNAL\",\"readOnly\":false,\"properties\":{\"default-base-location\":\"$location\"},\"storageConfigInfo\":{\"storageType\":\"S3\",\"roleArn\":\"$POLARIS_ROLE_ARN\",\"externalId\":\"$POLARIS_EXTERNAL_ID\",\"region\":\"$AWS_REGION\",\"allowedLocations\":[\"$location\"]$extra}}}"

# Polaris shows the spark_user secret only once: in the answer to the create call,
# or to a reset call.
code=$(call POST /principals '{"principal":{"name":"spark_user"}}')
case $code in
  201) echo "polaris-setup: principal spark_user created"; write=1 ;;
  409)
    if [ -s "$OUT" ]; then
      echo "polaris-setup: principal spark_user already present, credentials file kept"; write=0
    else
      code=$(call POST /principals/spark_user/reset '{}')
      [ "$code" = 200 ] || fail "reset spark_user: HTTP $code"
      echo "polaris-setup: principal spark_user already present, credentials reset"; write=1
    fi ;;
  *) fail "principal spark_user: HTTP $code: $(command cat "$ANSWER")" ;;
esac
if [ "$write" = 1 ]; then
  id=$(field clientId)
  secret=$(field clientSecret)
  [ -n "$id" ] && [ -n "$secret" ] || fail "no clientId or clientSecret in the answer"
  umask 077
  printf 'POLARIS_SPARK_CLIENT_ID=%s\nPOLARIS_SPARK_CLIENT_SECRET=%s\n' "$id" "$secret" >"$OUT.new"
  mv "$OUT.new" "$OUT"
  echo "polaris-setup: credentials written to secrets/spark_user.env"
fi

create "principal role spark_role" POST /principal-roles '{"principalRole":{"name":"spark_role"}}'
create "spark_role for spark_user" PUT /principals/spark_user/principal-roles '{"principalRole":{"name":"spark_role"}}'
create "catalog role lab_admin" POST /catalogs/lab_catalog/catalog-roles '{"catalogRole":{"name":"lab_admin"}}'
create "grant CATALOG_MANAGE_CONTENT" PUT /catalogs/lab_catalog/catalog-roles/lab_admin/grants '{"grant":{"type":"catalog","privilege":"CATALOG_MANAGE_CONTENT"}}'
create "lab_admin for spark_role" PUT /principal-roles/spark_role/catalog-roles/lab_catalog '{"catalogRole":{"name":"lab_admin"}}'

echo "polaris-setup: done"
```

Run: `chmod +x polaris/setup/setup.sh`

`command cat` in the script: the image `sh` has no alias, but `command` keeps the script safe if a
shell with aliases runs it.

- [ ] **Step 4: Add the three Polaris services to `docker-compose.yml`**

Insert under `services:`, after the `nessie` service and before `spark`:

```yaml
  polaris-bootstrap:
    image: ${POLARIS_ADMIN_TOOL_IMAGE}
    profiles: [polaris]
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      POLARIS_PERSISTENCE_TYPE: relational-jdbc
      QUARKUS_DATASOURCE_JDBC_URL: jdbc:postgresql://postgres:5432/polaris
      QUARKUS_DATASOURCE_USERNAME: polaris
      QUARKUS_DATASOURCE_PASSWORD: ${POLARIS_DB_PASSWORD}
    # Creates the Polaris tables in polaris_schema and the root principal. A second run skips.
    command: ["bootstrap", "-r", "POLARIS", "-c", "POLARIS,${POLARIS_ROOT_CLIENT_ID},${POLARIS_ROOT_CLIENT_SECRET}"]

  polaris:
    image: ${POLARIS_IMAGE}
    profiles: [polaris]
    depends_on:
      polaris-bootstrap:
        condition: service_completed_successfully
    environment:
      POLARIS_PERSISTENCE_TYPE: relational-jdbc
      QUARKUS_DATASOURCE_JDBC_URL: jdbc:postgresql://postgres:5432/polaris
      QUARKUS_DATASOURCE_USERNAME: polaris
      QUARKUS_DATASOURCE_PASSWORD: ${POLARIS_DB_PASSWORD}
      # Polaris calls STS with the AWS default credential chain (VM instance profile) and
      # assumes polaris-s3-access to vend S3 credentials to Spark.
      AWS_REGION: ${AWS_REGION}
      JAVA_OPTS_APPEND: -Xmx384m -XX:MaxDirectMemorySize=128m
    mem_limit: 1g
    ports:
      - "127.0.0.1:8181:8181"
      - "127.0.0.1:8182:8182"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8182/q/health/ready >/dev/null"]
      interval: 5s
      timeout: 5s
      retries: 30

  polaris-setup:
    image: ${POLARIS_SETUP_IMAGE}
    profiles: [polaris]
    depends_on:
      polaris:
        condition: service_healthy
    # The host UID, so that the spark container can read the credentials file.
    user: "${LAB_UID:-1000}"
    entrypoint: ["/bin/sh", "/setup/setup.sh"]
    environment:
      POLARIS_ROOT_CLIENT_ID: ${POLARIS_ROOT_CLIENT_ID}
      POLARIS_ROOT_CLIENT_SECRET: ${POLARIS_ROOT_CLIENT_SECRET}
      POLARIS_ROLE_ARN: ${POLARIS_ROLE_ARN}
      POLARIS_EXTERNAL_ID: ${POLARIS_EXTERNAL_ID}
      S3_BUCKET: ${S3_BUCKET}
      AWS_REGION: ${AWS_REGION}
      S3_ENDPOINT: ${S3_ENDPOINT:-}
      S3_PATH_STYLE_ACCESS: ${S3_PATH_STYLE_ACCESS:-false}
    volumes:
      - ./polaris/setup:/setup:ro
      - ./secrets:/secrets
```

- [ ] **Step 5: Make `spark` wait for `polaris-setup`**

In the `spark` service, add to `depends_on`:

```yaml
      polaris-setup:
        condition: service_completed_successfully
        required: false
```

- [ ] **Step 6: Write the Spark template `spark/conf/catalogs/polaris.conf`**

```text
# Catalog polaris: Polaris catalog lab_catalog. Spark authenticates as spark_user (never
# root) and writes with the S3 credentials that Polaris vends (role polaris-s3-access).
spark.sql.catalog.polaris                                     org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.polaris.type                                rest
spark.sql.catalog.polaris.uri                                 http://polaris:8181/api/catalog
spark.sql.catalog.polaris.warehouse                           lab_catalog
spark.sql.catalog.polaris.rest.auth.type                      oauth2
spark.sql.catalog.polaris.oauth2-server-uri                   http://polaris:8181/api/catalog/v1/oauth/tokens
spark.sql.catalog.polaris.credential                          ${POLARIS_SPARK_CLIENT_ID}:${POLARIS_SPARK_CLIENT_SECRET}
spark.sql.catalog.polaris.scope                               PRINCIPAL_ROLE:ALL
spark.sql.catalog.polaris.header.X-Iceberg-Access-Delegation  vended-credentials
```

- [ ] **Step 7: Extend `tests/catalog-selection.sh` and `tests/spark-config.sh`**

In `tests/catalog-selection.sh`, after the `COMPOSE_PROFILES=nessie adds nessie` line, add:

```bash
assert_eq "$(services polaris)" "polaris,polaris-bootstrap,polaris-setup,postgres,spark" "COMPOSE_PROFILES=polaris adds the polaris services"
```

In `tests/spark-config.sh`, before `finish`, add:

```bash
polaris=$(conf polaris)
assert_contains "$polaris" "spark.sql.catalog.polaris.uri                                 http://polaris:8181/api/catalog" "polaris block with polaris"
assert_not_contains "$polaris" '${POLARIS_SPARK_CLIENT' "polaris credentials rendered"
```

The polaris check needs `secrets/spark_user.env`, so it passes only after `polaris-setup` ran
(Step 9).

- [ ] **Step 8: Add `make sql-polaris`**

In `Makefile`, add `sql-polaris` to `.PHONY` and add, after `sql-nessie`:

```make
sql-polaris:
	docker compose exec spark spark-sql --conf spark.sql.defaultCatalog=polaris
```

- [ ] **Step 9: Start Polaris and run the tests to verify they pass**

Run:
```bash
sed -i 's/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=polaris/' .env
make up
docker compose logs polaris-bootstrap polaris-setup | grep -E "bootstrapped|polaris-setup"
tests/polaris-service.sh
tests/catalog-selection.sh
tests/spark-config.sh
```
Expected: the bootstrap log says `successfully bootstrapped` (or `already bootstrapped`), the setup
log ends with `polaris-setup: done`; every test ends with `all assertions passed`.

`tests/catalog-selection.sh` ends with `make up` with `COMPOSE_PROFILES=nessie`. Run `make up`
again afterwards, so that the stack matches `.env` (`polaris`).

If `make up` fails on the one-shot services with `--wait`, report the exact error to the
controller before you change the Makefile.

- [ ] **Step 10: Check a Polaris write by hand, then clean it**

Run:
```bash
docker compose exec -T spark spark-sql -S -e "CREATE NAMESPACE IF NOT EXISTS polaris.check;
CREATE TABLE polaris.check.t (id INT) USING iceberg;
INSERT INTO polaris.check.t VALUES (1);
SELECT count(*) FROM polaris.check.t;
DROP TABLE polaris.check.t PURGE;
DROP NAMESPACE polaris.check;" 2>/dev/null
docker compose exec -T spark bash -c 'aws s3 ls --recursive "s3://$S3_BUCKET/polaris/"'
```
Expected: `1`; the listing shows no object under `polaris/check/`. The VM role cannot write under
`polaris/` (Phase 1 test), so the insert proves the credential vending.

- [ ] **Step 11: Run lint and commit**

Run: `make lint`
Expected: `lint passed` and `no secrets found`.

```bash
git add docker-compose.yml polaris/setup/setup.sh spark/conf/catalogs/polaris.conf Makefile tests/polaris-service.sh tests/catalog-selection.sh tests/spark-config.sh
git commit -m "feat(polaris): add Polaris with relational-jdbc, setup and credential vending"
```

---

## Task 16: Catalog acceptance test for Polaris

**Files:**
- Modify: `tests/catalog-smoke.sh`

- [ ] **Step 1: Run the test to verify it fails**

Run: `tests/catalog-smoke.sh polaris; echo "exit=$?"`
Expected: `unknown catalog 'polaris'; usage: ...` and `exit=2`.

- [ ] **Step 2: Add the `polaris` case**

In `tests/catalog-smoke.sh`, replace the `case` block and its comment lines with:

```bash
# Per-catalog policy.
# own_files=1: the VM role deletes the table files after the drop (Nessie never deletes files).
# own_files=0: DROP TABLE ... PURGE deletes the files with the credentials that the catalog
# vends; the VM role cannot write under polaris/.
case $catalog in
  nessie) prefix=nessie; drop_sql="DROP TABLE IF EXISTS %s"; own_files=1 ;;
  polaris) prefix=polaris; drop_sql="DROP TABLE IF EXISTS %s PURGE"; own_files=0 ;;
  *) echo "unknown catalog '$catalog'; usage: tests/catalog-smoke.sh nessie|polaris" >&2; exit 2 ;;
esac
```

- [ ] **Step 3: Fail when the purge leaves files**

In the `cleanup` function, replace

```bash
  if ((own_files)) && [[ -n $root ]]; then
```

with

```bash
  if ((!own_files)) && [[ -n $root ]]; then
    left=$(docker compose exec -T spark aws s3 ls --recursive "$root/" 2>/dev/null || true)
    if [[ -n $left ]]; then
      echo "  FAIL - files left under $root/ after the purge:"
      echo "$left"
      exit 1
    fi
  elif ((own_files)) && [[ -n $root ]]; then
```

An `exit` in an EXIT trap sets the exit code of the script, so a purge that leaves files fails
the test.

- [ ] **Step 4: Run the test to verify it passes**

Run: `tests/catalog-smoke.sh polaris; echo "exit=$?"`
Expected: every line `ok`, `all assertions passed`, `exit=0`. The `s3sign` check does not run
(Nessie only).

- [ ] **Step 5: Check that nothing is left under `polaris/`**

Run: `docker compose exec -T spark bash -c 'aws s3 ls --recursive "s3://$S3_BUCKET/polaris/"'`
Expected: no object of a `t_<number>` table.

- [ ] **Step 6: Run the smoke test with each catalog**

Run:
```bash
make smoke-test
sed -i 's/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=nessie/' .env && make up && make smoke-test
sed -i 's/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=/' .env && make up && make smoke-test
```
Expected: the first run tests Polaris, the second Nessie, the third only the base stack
(`no catalog in COMPOSE_PROFILES: only the base tests ran`). Each run exits 0. At the end
`.env` has `COMPOSE_PROFILES=` (no catalog), as the user wants by default.

- [ ] **Step 7: Run lint and commit**

Run: `make lint`
Expected: `lint passed` and `no secrets found`.

```bash
git add tests/catalog-smoke.sh
git commit -m "test: add the polaris case to the catalog acceptance test"
```

---

## Task 17: Notes, README and handoff

**Files:**
- Modify: `NOTES.md`
- Modify: `README.md`
- Modify: `docs/HANDOFF.md`

Documentation follows ASD-STE100 (`CLAUDE.md`): short direct sentences, one action per
procedural step, one term for one concept.

- [ ] **Step 1: Add the deviations to `NOTES.md`**

After the D10 entry, add:

```markdown
### D11 — The catalogs are optional
- Requirement (sections 5.1 and 7): the stack has the services `polaris` and `nessie`, and the
  Makefile has the target `up-baseline`.
- Lab: each catalog is a Compose profile (`polaris`, `nessie`, later `baseline`). The catalogs are
  off by default. `COMPOSE_PROFILES` in `.env` selects them. There is no `up-baseline`: add
  `baseline` to `COMPOSE_PROFILES`.
- Why: user decision (2026-10-29). The user chooses the catalog for each test. The catalogs do
  not have to run together.

### D12 — `polaris-bootstrap` is required
- Spec (section 5): add `polaris-bootstrap` only if the Polaris docs require it.
- Lab: Polaris 1.8.0 with `relational-jdbc` does not create its tables. The admin tool
  (`bootstrap -r POLARIS -c POLARIS,<root id>,<root secret>`) creates them and the root
  principal. A second run skips, so the job runs on every `make up`.

### D13 — `polaris-setup` reads JSON with `sed`
- Requirement (section 5.1): the setup image has `curl` and `jq`.
- Lab: the pinned image `alpine/curl` has no `jq`. The script is POSIX `sh` and reads the few
  JSON fields it needs with `sed`.
- Why: `apk add jq` at every start needs network access and installs an unpinned version.
```

- [ ] **Step 2: Add the Polaris finding to `NOTES.md`**

After the F2 entry, add:

```markdown
### F3 — Polaris purge (Polaris 1.8.0, checked 2026-10-29)
- The catalog property `polaris.config.drop-with-purge.enabled` (default false) controls the
  server-side purge: a REST `DELETE ...?purgeRequested=true` gets HTTP 403 when it is false.
- Spark `DROP TABLE ... PURGE` does not use the server-side purge. Spark deletes the files itself,
  with the S3 credentials that Polaris vends. It works also when the property is false.
- Lab: the property stays false. `tests/catalog-smoke.sh polaris` drops its table with
  `DROP TABLE ... PURGE` and fails when a file is left under `polaris/`.
```

- [ ] **Step 3: Replace the open investigation in `NOTES.md`**

Remove the line `- Polaris \`relational-jdbc\` bootstrap (admin tool job).` from "Open
investigations" (D12 answers it).

- [ ] **Step 4: Update `README.md`**

1. Replace the "Status" section text, from `Work in progress.` to the line
   `Open a Spark SQL shell on the Nessie catalog with \`make sql-nessie\`.`, with:

```markdown
Work in progress. Stage 1 (AWS scripts), Phase 1 (Postgres, Spark image), Phase 2 (Polaris)
and Phase 3 (Nessie) are done.

The catalogs are off by default. To choose them:

1. Set `COMPOSE_PROFILES` in `.env`, for example `COMPOSE_PROFILES=polaris` or
   `COMPOSE_PROFILES=nessie`. Leave it empty for no catalog.
2. Run `make up`. It starts the catalogs in `COMPOSE_PROFILES` and stops the others.
   Their data stays.
3. Run `make smoke-test`. It tests the base stack and each catalog that is on.
4. Run `make down` when you stop working.

Open a Spark SQL shell on a catalog with `make sql-polaris` or `make sql-nessie`.
```

2. In the table of "Access from your machine", add after the Nessie management row:

```markdown
| Polaris API | 8181 | <http://localhost:8181/api/management/v1/catalogs> (needs a token) |
| Polaris management (health) | 8182 | <http://localhost:8182/q/health/ready> |
```

3. In the SSH tunnel command, add the two lines `-L 8181:127.0.0.1:8181 \` and
   `-L 8182:127.0.0.1:8182 \` after the `9000` line, and in the SSM step 2 add `8181, 8182` to
   the list of ports.

4. Add a row to the documents table, after the Phase 3 plan:

```markdown
| [Plan: Phase 2 (Polaris)](docs/superpowers/plans/2026-10-29-phase2-polaris.md) | Task-by-task implementation plan |
```

- [ ] **Step 5: Update `docs/HANDOFF.md`**

1. In the "Where we are" table, after the row `Plan (Phase 3)`, add:

```markdown
| Plan (Phase 2) | `docs/superpowers/plans/2026-10-29-phase2-polaris.md` — Tasks 13-17 |
```

2. Replace the rows `GitHub issues`, `Phase 3 (Nessie)` and `Next step` with:

```markdown
| GitHub issues | #1-#9, #13-#15 and #17-#21, one per plan task |
| Phase 3 (Nessie) | Merged (PR #16) |
| Phase 2 (Polaris) and optional catalogs | Done on branch `phase2-polaris`. PR pending |
| Next step | Write the Phase 4 plan (baseline `rest-fixture`) |
```

3. In "Decisions already taken with the user", add:

```markdown
11. The catalogs are off by default; `COMPOSE_PROFILES` in `.env` selects them. The catalogs do
    not have to run together (2026-10-29, `NOTES.md` D11).
```

- [ ] **Step 6: Run lint and commit**

Run: `make lint`
Expected: `lint passed` and `no secrets found`.

```bash
git add NOTES.md README.md docs/HANDOFF.md
git commit -m "docs: record the Polaris findings and the optional catalogs"
```

---

## Out of scope for this plan

- Phase 4 (baseline): `rest-fixture`, the `baseline` profile, `make sql-rest`.
- On-premise S3 for Polaris: `polaris-setup` passes `endpoint` and `pathStyleAccess` when
  `S3_ENDPOINT` is set, and Polaris may need `stsEndpoint` or `stsUnavailable`. Not tested.
- Static S3 keys for Polaris (on-premise, no IMDS).
- Scenario 7 (read-only principal `reader_user`).

## Execution notes (after review)

The code blocks above are the plan as written. The reviews of each task changed the code.
The code in the repository is the reference; read it, not this plan, before Phase 4.

- Task 13 (`4b44eed`): `make up` stops with `|| exit 1` when `docker compose config` fails.
  `tests/catalog-selection.sh` restores the `.env` selection with a trap and prints the
  `make up` log on failure.
- Task 14 (`e263105`): the entrypoint splits `LAB_CATALOGS` with `IFS=', ' read -ra` (no
  globbing), sources `secrets/spark_user.env` only when `polaris` is selected and without
  `set -a`, writes the rendered file with mode 600 (`umask 077`), and warns on `*` and on a
  profile without a template. The common configuration sets `spark.redaction.regex` with
  `credential`. `tests/spark-config.sh` checks stdout and stderr apart (`conf_err`).
- Task 15 (`865efef`):
  - `polaris-bootstrap` runs `bootstrap -f /tmp/root.yaml` through `/bin/sh -c`, with the root
    credentials in `LAB_ROOT_ID`/`LAB_ROOT_SECRET`: the image entrypoint logs its command line.
  - `polaris` gets the optional static keys `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`.
  - `setup.sh` retries the root token call, removes its temporary files with a trap, checks the
    required values and `S3_PATH_STYLE_ACCESS`, keeps a credentials file only when a token call
    with it works, prints a restart hint after a reset, and prints "set" for PUT calls.
  - `tests/polaris-service.sh` keeps the caller's `COMPOSE_PROFILES`, checks that the bootstrap
    log does not show the root secret, checks the `spark_role` assignment, and compares the
    Spark client id with the id in the credentials file.
  - `.env.example` lists the characters that the root id and secret must not contain.
- Task 16 (`b539abe`, `09b1cbf`): `tests/catalog-smoke.sh` keeps the caller's
  `COMPOSE_PROFILES`, restarts the stack with `docker compose stop` and
  `docker compose up -d --wait` (dependency order), and fails when a Polaris table cannot be
  purged or leaves files.
- Task 17 (`a09c23c`): D12 records the bootstrap file. F4 lists where the Polaris secrets are.
- Final review: `setup.sh` fails with a hint when `secrets/` is not writable (Docker creates a
  missing bind-mount folder as root); the entrypoint warns when `polaris` is selected and the
  credentials file is missing; `tests/spark-config.sh` uses the fake profile `no-such-catalog`,
  because Phase 4 adds `catalogs/baseline.conf`.
- Phase 4 note: `tests/smoke-test.sh` assumes that the profile, the service and the Spark
  catalog have the same name. For `baseline` they differ (service `rest-fixture`, catalog
  `rest`): the Phase 4 plan needs a map there.

