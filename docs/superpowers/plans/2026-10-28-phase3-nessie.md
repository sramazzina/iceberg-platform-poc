# Iceberg catalog lab — Phase 3 (Nessie) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Project Nessie as an Iceberg REST catalog with a JDBC version store on Postgres and a warehouse on `s3://${S3_BUCKET}/nessie/`, and register it in Spark as catalog `nessie`.

**Architecture:** A `nessie` service in `docker-compose.yml`, configured only with environment variables (no `nessie/application.properties`). Nessie writes table metadata with the VM instance profile (AWS default credential chain). S3 request signing is disabled, so Spark writes data files with its own instance-profile credentials, as the spec requires (section 5.3). Spark gets a static `nessie` catalog block in `spark/conf/spark-defaults.conf`. A generic `tests/catalog-smoke.sh CATALOG` implements the catalog acceptance test of spec section 6; Phase 2 (Polaris) and Phase 4 (baseline) reuse it.

**Tech Stack:** Project Nessie 0.109.0 (Quarkus, Java 21), PostgreSQL 18, Spark 4.1.3 with the Iceberg 1.11.0 REST client, Docker Compose, Bash, jq.

**Spec:** `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md`

---

## Phase order

The spec orders the phases 2 (Polaris), 3 (Nessie), 4 (baseline). The user decided on
2026-10-28 to do Nessie first and Polaris later. Consequences:

- The Spark catalog block for Nessie has no variable, so `spark-defaults.conf` stays a
  static file in this phase. The template rendering of spec section 5.2 comes with Phase 2,
  because only the Polaris block needs secrets.
- `tests/catalog-smoke.sh` is written here. Phase 2 adds the `polaris` case.
- `NOTES.md` records the new order (Task 12).

## Facts verified on 2026-10-28 (Nessie 0.109.0, on this VM)

Sources: `servers/quarkus-server/src/main/resources/application.properties`,
`catalog/files/api/src/main/java/org/projectnessie/catalog/files/config/S3BucketOptions.java`
and `site/docs/guides/iceberg-rest.md` at tag `nessie-0.109.0`, plus throwaway containers on
this VM.

- Version store: `NESSIE_VERSION_STORE_TYPE=JDBC2` (`JDBC` is deprecated) with
  `NESSIE_VERSION_STORE_PERSIST_JDBC_DATASOURCE=postgresql` and
  `QUARKUS_DATASOURCE_POSTGRESQL_JDBC_URL/USERNAME/PASSWORD`. Nessie creates the tables
  `public.refs2` and `public.objs2` itself and creates branch `main` on first start.
- Warehouse: `NESSIE_CATALOG_DEFAULT_WAREHOUSE=<name>` and
  `NESSIE_CATALOG_WAREHOUSES_<NAME>_LOCATION=s3://...` are both mandatory. Without them
  `GET /iceberg/v1/config` returns HTTP 500. The config response gives `defaults.prefix=main`
  and `defaults.warehouse` = the location without the trailing slash.
- S3 credentials: the default `auth-type` is `STATIC` (static keys).
  `NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_AUTH_TYPE=APPLICATION_GLOBAL` uses the AWS
  default credential chain, so the instance profile through IMDSv2.
- S3 request signing is **on** by default: every S3 request of Spark goes through
  `POST /iceberg/v1/main/s3sign/...` on Nessie. With
  `NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_REQUEST_SIGNING_ENABLED=false`, Spark's S3FileIO
  uses its own credentials. No extra Spark property is needed.
- STS credential vending (`client-iam`, `server-iam`) is off by default. Not tested.
- The object-store health check calls S3 `HeadBucket`. The VM role allows `s3:ListBucket`
  only with an `s3:prefix` condition, so `HeadBucket` returns 403 and `/q/health/ready`
  reports DOWN. `NESSIE_CATALOG_OBJECT_STORES_HEALTH_CHECK_ENABLED=false` removes this check.
- Ports: HTTP 19120 (Iceberg REST at `/iceberg`, native API at `/api/v2`), management 9000
  (`/q/health/ready`). The image has `curl` and `bash`.
- Image: UBI 9 with OpenJDK 21, user `nessie` (UID 10000). The JVM takes 80 % of the
  container memory, and the objects cache takes 70 % of the heap. With `mem_limit: 1g` and
  `JAVA_OPTS_APPEND=-Xmx512m` Nessie starts in about 7 s.
- Authentication is off by default (`nessie.server.authentication.enabled=false`).
- Spark REST catalog that worked: `type=rest`, `uri=http://nessie:19120/iceberg/main`.
  Do not set `prefix` or `warehouse` on the client (Nessie docs).

## Conventions for every task

- All file content, comments, commit messages: English.
- Commit messages: Conventional Commits style, **no `Co-Authored-By` line** (`CLAUDE.md`).
- Do not push. The controller pushes the batch and opens the PR.
- Never write a real account ID, bucket name, ARN, external ID, password or secret into a
  tracked file. `.env` holds real values: never print it, never commit it.
- All tasks run on the EC2 VM, in the repository clone, with `.env` filled.
- Never run `aws/setup.sh` or `aws/teardown.sh`, and never change an AWS resource. The
  `aws` CLI runs only inside the `spark` container, as part of a test.
- No `${VAR:?}` in `docker-compose.yml`: `make lint` renders the file against `.env.example`,
  where `S3_BUCKET` is empty.
- In this shell `cat` is an alias for a missing `bat`: use `command cat` or the Write tool.
- Branch: `phase3-nessie` (already checked out).

## File map

| File | Responsibility | Task |
|---|---|---|
| `docker-compose.yml` | `nessie` service; `spark` waits for `nessie` | 10, 11 |
| `tests/nessie-service.sh` | Health, branch `main`, JDBC tables, warehouse of the Nessie service | 10 |
| `spark/conf/spark-defaults.conf` | Spark catalog `nessie` | 11 |
| `tests/catalog-smoke.sh` | Catalog acceptance test of spec section 6, per catalog | 11 |
| `Makefile` | `sql-nessie`, `smoke-test` with the Nessie tests | 10, 11 |
| `NOTES.md`, `README.md`, `docs/HANDOFF.md` | Deviations, findings, status | 12 |

---

## Task 10: Nessie service with a JDBC version store

**Files:**
- Modify: `docker-compose.yml`
- Modify: `Makefile`
- Test: `tests/nessie-service.sh`

- [ ] **Step 1: Write the failing test**

`tests/nessie-service.sh`:

```bash
#!/usr/bin/env bash
# Checks the nessie service: readiness, default branch, JDBC version store tables,
# and the warehouse that the Iceberg REST endpoint gives to clients.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
set -a; source .env; set +a

# curl runs inside the nessie container: Nessie publishes no port on the host.
nessie_get() { docker compose exec -T nessie curl -fsS "$1" 2>&1 || echo "request failed: $1"; }

echo "nessie"
ready=$(nessie_get http://127.0.0.1:9000/q/health/ready)
assert_contains "$ready" "UP" "readiness check is UP"
assert_not_contains "$ready" "request failed" "readiness endpoint answers HTTP 200"

branch=$(nessie_get http://127.0.0.1:19120/api/v2/trees/main | jq -r '.reference.type + ":" + .reference.name' 2>&1 || true)
assert_eq "$branch" "BRANCH:main" "default branch main exists"

tables=$(docker compose exec -T postgres psql -U postgres -d nessie -tAc \
  "SELECT string_agg(tablename || ':' || tableowner, ',' ORDER BY tablename) FROM pg_tables WHERE schemaname = 'public'" 2>&1 || true)
assert_eq "$tables" "objs2:nessie,refs2:nessie" "JDBC2 version store tables owned by nessie"

config=$(nessie_get http://127.0.0.1:19120/iceberg/v1/config | jq -r '.defaults.prefix + " " + .defaults.warehouse' 2>&1 || true)
assert_eq "$config" "main s3://$S3_BUCKET/nessie" "Iceberg REST prefix main and warehouse on nessie/"

finish
```

Run: `chmod +x tests/nessie-service.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/nessie-service.sh`
Expected: FAIL on every check (`service "nessie" is not running` or `no such service: nessie`
inside the FAIL messages), last line `5 assertion(s) failed`.

- [ ] **Step 3: Add the `nessie` service to `docker-compose.yml`**

Insert this block under `services:`, after the `postgres` service and before `spark`:

```yaml
  nessie:
    image: ${NESSIE_IMAGE}
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      # Version store: JDBC2 on the database nessie. Nessie creates its tables itself.
      NESSIE_VERSION_STORE_TYPE: JDBC2
      NESSIE_VERSION_STORE_PERSIST_JDBC_DATASOURCE: postgresql
      QUARKUS_DATASOURCE_POSTGRESQL_JDBC_URL: jdbc:postgresql://postgres:5432/nessie
      QUARKUS_DATASOURCE_POSTGRESQL_USERNAME: nessie
      QUARKUS_DATASOURCE_POSTGRESQL_PASSWORD: ${NESSIE_DB_PASSWORD}
      # Iceberg REST warehouse on the nessie/ prefix.
      NESSIE_CATALOG_DEFAULT_WAREHOUSE: lab
      NESSIE_CATALOG_WAREHOUSES_LAB_LOCATION: s3://${S3_BUCKET}/nessie/
      NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_REGION: ${AWS_REGION}
      NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_ENDPOINT: ${S3_ENDPOINT:-}
      NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_PATH_STYLE_ACCESS: ${S3_PATH_STYLE_ACCESS:-false}
      # AWS default credential chain: the VM instance profile through IMDSv2.
      NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_AUTH_TYPE: APPLICATION_GLOBAL
      # Spark signs its own S3 requests with the VM instance profile (spec section 5.3).
      NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_REQUEST_SIGNING_ENABLED: "false"
      # The check calls S3 HeadBucket, which the prefix-scoped VM policy denies (NOTES.md D10).
      NESSIE_CATALOG_OBJECT_STORES_HEALTH_CHECK_ENABLED: "false"
      JAVA_OPTS_APPEND: -Xmx512m
    mem_limit: 1g
    ports:
      - "127.0.0.1:19120:19120"
      - "127.0.0.1:9000:9000"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:9000/q/health/ready >/dev/null"]
      interval: 5s
      timeout: 5s
      retries: 30
```

The ports are published on `127.0.0.1` only (spec section 5.4), for the SSH tunnel from the
user's machine. The tests do not use them.

- [ ] **Step 4: Start Nessie and run the test to verify it passes**

Run:
```bash
docker compose up -d --wait nessie
tests/nessie-service.sh
```
Expected: every line `ok`, last line `all assertions passed`.

If Nessie does not start, read `docker compose logs nessie`. A known risk: the empty
`NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_ENDPOINT` (AWS case). If an empty endpoint makes
Nessie fail, remove that one line, run again, and report the error text to the controller.
Do not change any other setting without approval.

- [ ] **Step 5: Verify the restart keeps the version store**

Run:
```bash
docker compose restart nessie
docker compose up -d --wait nessie
tests/nessie-service.sh
docker compose logs nessie | grep -E "JDBC2 version store" | tail -n 1
```
Expected: all assertions passed; the last log line says the tables already exist (no
`created`).

- [ ] **Step 6: Add the Nessie test to `make smoke-test`**

In `Makefile`, replace the `smoke-test` target with:

```make
smoke-test:
	tests/postgres-init.sh
	tests/s3-access.sh
	tests/nessie-service.sh
```

- [ ] **Step 7: Run lint and the smoke test**

Run: `make lint && make smoke-test`
Expected: `lint passed`, `no secrets found`, then every test ends with `all assertions passed`
or its `ok` lines, exit code 0.

- [ ] **Step 8: Commit**

```bash
git add docker-compose.yml Makefile tests/nessie-service.sh
git commit -m "feat(nessie): add Nessie with a JDBC version store and an S3 warehouse"
```

---

## Task 11: Spark catalog `nessie` and the catalog acceptance test

**Files:**
- Modify: `spark/conf/spark-defaults.conf`
- Modify: `docker-compose.yml`
- Modify: `Makefile`
- Test: `tests/catalog-smoke.sh`

- [ ] **Step 1: Write the failing test**

`tests/catalog-smoke.sh`:

```bash
#!/usr/bin/env bash
# Catalog acceptance test (spec section 6). Usage: tests/catalog-smoke.sh CATALOG
# Creates a table in CATALOG, writes two rows and reads them, checks that the files
# are under the S3 prefix of the catalog, restarts the stack, and reads the rows again.
# The table gets a unique name and is removed at the end, files included.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"
set -a; source .env; set +a

catalog=${1:-}
case $catalog in
  nessie) prefix=nessie ;;
  *) echo "usage: tests/catalog-smoke.sh nessie" >&2; exit 2 ;;
esac

table="$catalog.smoke.t_$(date +%s)"
root=""

# sql STATEMENTS: runs spark-sql in the spark container. Prints the result rows; on
# failure prints the end of the Spark log and "spark-sql failed".
sql() {
  docker compose exec -T spark bash -c \
    'spark-sql -S -e "$1" 2>/tmp/catalog-smoke.err || { tail -n 20 /tmp/catalog-smoke.err; echo "spark-sql failed"; }' \
    _ "$1"
}

rows() { sql "SELECT concat('row=', id, ':', name) FROM $table ORDER BY id" | grep '^row=' || true; }

cleanup() {
  sql "DROP TABLE IF EXISTS $table" >/dev/null
  if [[ -n $root ]]; then
    docker compose exec -T spark aws s3 rm --recursive --quiet "$root/" >/dev/null 2>&1 \
      || echo "  warn - could not delete $root/"
  fi
}
trap cleanup EXIT

echo "catalog $catalog"
out=$(sql "CREATE NAMESPACE IF NOT EXISTS $catalog.smoke;
CREATE TABLE $table (id INT, name STRING) USING iceberg;
INSERT INTO $table VALUES (1, 'a'), (2, 'b');")
assert_not_contains "$out" "spark-sql failed" "create a namespace and a table, insert two rows"
assert_eq "$(rows)" $'row=1:a\nrow=2:b' "read the two rows"

path=$(sql "SELECT file_path FROM $table.files" | grep '^s3://' | head -n 1 || true)
want="s3://$S3_BUCKET/$prefix/"
assert_eq "${path:0:${#want}}" "$want" "data file under the $prefix/ prefix"
if [[ $path == */data/* ]]; then root=${path%/data/*}; fi

listing=$(docker compose exec -T spark aws s3 ls --recursive "${root:-$want}/" 2>&1 || true)
assert_contains "$listing" ".parquet" "aws s3 ls shows the data file"
assert_contains "$listing" ".metadata.json" "aws s3 ls shows the table metadata"

if [[ $catalog == nessie ]]; then
  assert_not_contains "$(docker compose logs nessie 2>&1)" "s3sign" \
    "Spark uses its own S3 credentials (no request signing by Nessie)"
fi

echo "restart"
if docker compose restart >/dev/null 2>&1 && docker compose up -d --wait >/dev/null 2>&1; then
  pass "docker compose restart"
else
  fail "docker compose restart"
fi
assert_eq "$(rows)" $'row=1:a\nrow=2:b' "the table and its rows survive the restart"

finish
```

Run: `chmod +x tests/catalog-smoke.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/catalog-smoke.sh nessie`
Expected: FAIL on `create a namespace and a table, insert two rows`; the printed Spark log
says that catalog `nessie` is not found.

- [ ] **Step 3: Add the catalog to `spark/conf/spark-defaults.conf`**

Append:

```text
# Catalog nessie: Nessie Iceberg REST endpoint, branch main. Spark writes the data files
# with the VM instance profile (Nessie request signing is disabled).
spark.sql.catalog.nessie        org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.nessie.type   rest
spark.sql.catalog.nessie.uri    http://nessie:19120/iceberg/main
```

- [ ] **Step 4: Make `spark` wait for `nessie`**

In `docker-compose.yml`, in the `spark` service, after `init: true`, add:

```yaml
    depends_on:
      nessie:
        condition: service_healthy
```

- [ ] **Step 5: Rebuild Spark and run the test to verify it passes**

Run:
```bash
docker compose up -d --build --wait
tests/catalog-smoke.sh nessie
```
Expected: every line `ok`, last line `all assertions passed`. The run takes about 2 minutes
(each `spark-sql` call starts a JVM, and the stack restarts once).

- [ ] **Step 6: Prove that the signing check can fail**

The check `Spark uses its own S3 credentials` is useful only if Nessie logs the `s3sign`
requests. Prove it once, with no change to tracked files:

```bash
docker compose run --rm -d --no-deps --name nessie-signing-probe \
  -e NESSIE_VERSION_STORE_TYPE=IN_MEMORY \
  -e NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_REQUEST_SIGNING_ENABLED=true nessie
```

The probe has an in-memory version store, so it does not touch the database `nessie` of the
real service.

Then run, against that container, a short spark-sql job with
`--conf spark.sql.catalog.p=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.p.type=rest --conf spark.sql.catalog.p.uri=http://nessie-signing-probe:19120/iceberg/main`
that creates `p.probe.t` and inserts one row. Check that
`docker logs nessie-signing-probe | grep -c s3sign` is greater than 0. Then remove the
container (`docker rm -f nessie-signing-probe`) and delete the files of `p.probe.t` under
`s3://$S3_BUCKET/nessie/probe/` with `aws s3 rm --recursive` in the spark container.
Report the `s3sign` count.

If the count is 0 (Nessie does not log these requests), do not keep a check that cannot fail:
remove the `if [[ $catalog == nessie ]]` block from `tests/catalog-smoke.sh` and report it to
the controller.

- [ ] **Step 7: Add the Makefile targets**

In `Makefile`:

1. Add `sql-nessie` to the `.PHONY` line.
2. Add the target, after `logs`:

```make
sql-nessie:
	docker compose exec spark spark-sql --conf spark.sql.defaultCatalog=nessie
```

3. Replace the `smoke-test` target with:

```make
smoke-test:
	tests/postgres-init.sh
	tests/s3-access.sh
	tests/nessie-service.sh
	tests/catalog-smoke.sh nessie
```

- [ ] **Step 8: Check `make sql-nessie`**

Run: `docker compose exec -T spark spark-sql -S --conf spark.sql.defaultCatalog=nessie -e "SHOW NAMESPACES" 2>/dev/null`
Expected: the command ends with exit code 0 and lists `smoke` (left by the test).

- [ ] **Step 9: Run lint, the image test and the smoke test**

Run: `make lint && tests/spark-image.sh && make smoke-test`
Expected: `lint passed`, `no secrets found`, all assertions passed in every test, exit code 0.

- [ ] **Step 10: Check that the tests leave no object behind**

Run: `docker compose exec -T spark bash -c 'aws s3 ls --recursive "s3://$S3_BUCKET/nessie/"'`
Expected: no `.parquet` and no `.metadata.json` object of a `t_<number>` table.

- [ ] **Step 11: Commit**

```bash
git add spark/conf/spark-defaults.conf docker-compose.yml Makefile tests/catalog-smoke.sh
git commit -m "feat(spark): add the nessie catalog and the catalog acceptance test"
```

---

## Task 12: Notes, README and handoff

**Files:**
- Modify: `NOTES.md`
- Modify: `README.md`
- Modify: `docs/HANDOFF.md`

Documentation follows ASD-STE100 (`CLAUDE.md`): short direct sentences, one action per
procedural step, one term for one concept.

- [ ] **Step 1: Add the deviations to `NOTES.md`**

After the D8 entry, add:

```markdown
### D9 — Phase 3 (Nessie) before Phase 2 (Polaris)
- Requirement (section 8): the phases run in the order 2 (Polaris), 3 (Nessie), 4 (baseline).
- Lab: Phase 3 runs before Phase 2 (user decision, 2026-10-28).
- Why: Nessie has no credential vending and no bootstrap job, so it is the shorter path to a
  first catalog. `spark-defaults.conf` stays a static file until Phase 2, because only the
  Polaris catalog block needs secrets.

### D10 — Nessie object-store health check disabled
- Nessie 0.109.0 checks each warehouse with S3 `HeadBucket` in its readiness check.
- The VM role allows `s3:ListBucket` only with an `s3:prefix` condition (least privilege),
  so `HeadBucket` returns 403 and the readiness check reports DOWN.
- Lab: `NESSIE_CATALOG_OBJECT_STORES_HEALTH_CHECK_ENABLED=false`. The readiness check still
  covers the database connection. `tests/catalog-smoke.sh nessie` checks the S3 access.
```

- [ ] **Step 2: Replace the Nessie open investigation in `NOTES.md`**

Remove the line `- Nessie credential vending (\`client-iam\`, \`server-iam\`).` from
"Open investigations", and add this section before "Open investigations":

```markdown
## Findings

### F1 — Nessie S3 credentials (Nessie 0.109.0, checked 2026-10-28)
- Nessie reads and writes table metadata with its own server credentials. The lab sets
  `auth-type=APPLICATION_GLOBAL`: the AWS default credential chain, so the VM instance profile.
  The default `auth-type` is `STATIC` (static keys).
- Nessie gives clients S3 access in three ways:
  - **Request signing** (on by default): the client sends every S3 request to Nessie
    (`/iceberg/v1/{prefix}/s3sign/...`) for signing. The client needs no S3 credentials.
  - **Credential vending** with STS: `client-iam` (vended to clients) and `server-iam`
    (used by Nessie). Both are off by default. They need `assume-role` (a role ARN) and,
    outside AWS, `sts-endpoint`. The lab does not test them.
  - **Client credentials**: with request signing disabled, the client uses its own credentials.
- Lab: request signing is disabled. Spark writes the data files with the VM instance profile,
  as spec section 5.3 requires for `nessie/`.
- Sources: `S3BucketOptions.java`, `S3Iam.java`, `S3ClientIam.java`, `S3ServerIam.java` and
  `site/docs/guides/iceberg-rest.md` at tag `nessie-0.109.0`.
```

- [ ] **Step 3: Update the status in `README.md`**

Replace the "Status" section text, from `Work in progress.` to the end of the numbered list,
with:

```markdown
Work in progress. Stage 1 (AWS scripts) and Phase 1 (Postgres, Spark image) are done.
Phase 3 adds Nessie, before Phase 2 (Polaris), see `NOTES.md` D9.

Quick check on the VM:

1. Run `make up`.
2. Run `make smoke-test`.
3. Run `make down`.

Open a Spark SQL shell on the Nessie catalog with `make sql-nessie`.
```

- [ ] **Step 4: Update `docs/HANDOFF.md`**

In the "Where we are" table, replace the Phase 1 row and the "Next step" row with:

```markdown
| Phase 1 (Postgres, Spark image, S3 acceptance test) | Merged (PR #11) |
| Phase 3 (Nessie) | Done on branch `phase3-nessie`. PR pending. Phase 2 (Polaris) comes later (`NOTES.md` D9) |
| Next step | Write the Phase 2 plan (Polaris) |
```

- [ ] **Step 5: Run lint**

Run: `make lint`
Expected: `lint passed` and `no secrets found`.

- [ ] **Step 6: Commit**

```bash
git add NOTES.md README.md docs/HANDOFF.md
git commit -m "docs: record the Nessie findings and the phase order"
```

---

## Out of scope for this plan

- Phase 2 (Polaris): the `polaris` catalog, `polaris-setup`, the template rendering of
  `spark-defaults.conf`, the `polaris` case of `tests/catalog-smoke.sh`, `make sql-polaris`.
- Phase 4 (baseline): `rest-fixture`, `make up-baseline`, `make sql-rest`.
- On-premise S3 for Nessie with static keys (`auth-type=STATIC` and a `urn:nessie-secret`
  reference): the lab runs on AWS. The endpoint and path-style options are already read from
  `.env`.
- Nessie authentication and authorization (scenario 7 documents the model).
