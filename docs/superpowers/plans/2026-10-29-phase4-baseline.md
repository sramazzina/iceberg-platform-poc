# Iceberg catalog lab — Phase 4 (baseline `rest-fixture`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the optional baseline catalog `apache/iceberg-rest-fixture` (Compose profile `baseline`, service `rest-fixture`, Spark catalog `rest`, S3 prefix `rest/`) and make the Phase 2 acceptance test pass on it.

**Architecture:** `rest-fixture` is one more Compose profile, off by default. Its JDBC catalog is a SQLite file on a named volume, so the catalog survives a restart. The fixture and Spark both use the VM instance profile (IMDSv2) for S3. The Spark entrypoint already renders `spark/conf/catalogs/<profile>.conf` for each profile in `COMPOSE_PROFILES`, so the new template `baseline.conf` is enough on the Spark side. The test runner gets a map from the service to the Spark catalog, because for this profile the names differ.

**Tech Stack:** `apache/iceberg-rest-fixture:1.10.1` (Iceberg JDBC catalog on SQLite, `S3FileIO`), Spark 4.1.3 with the Iceberg 1.11.0 REST client, Docker Compose profiles, Bash.

**Spec:** `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md`, sections 5.2, 5.4, 5.6, 6 (updated on 2026-10-29).

---

## Facts verified on 2026-10-29 (`apache/iceberg-rest-fixture:1.10.1`, on this VM)

Sources: `docker image inspect` and throwaway containers on this VM.

- Command `java -jar iceberg-rest-adapter.jar`, user `iceberg` (uid 1000), port 8181
  (`REST_PORT`), image healthcheck `curl --fail http://localhost:$REST_PORT/v1/config`.
  The image has `curl`.
- Defaults: `CATALOG_CATALOG__IMPL=org.apache.iceberg.jdbc.JdbcCatalog`,
  `CATALOG_URI=jdbc:sqlite:/tmp/iceberg_catalog.db`. The catalog in `/tmp` is lost when the
  container is recreated.
- Environment variables `CATALOG_<NAME>` become catalog properties: `__` becomes `-`, `_`
  becomes `.` (for example `CATALOG_IO__IMPL` → `io-impl`).
- `/home/iceberg` exists and belongs to `iceberg`. A named volume mounted there gets the same
  owner, and the fixture can write `/home/iceberg/catalog.db`. A volume mounted on
  `/home/iceberg/data` (not in the image) is owned by root: `Permission denied`.
- With `CATALOG_URI=jdbc:sqlite:/home/iceberg/catalog.db`,
  `CATALOG_WAREHOUSE=s3://<bucket>/rest/`,
  `CATALOG_IO__IMPL=org.apache.iceberg.aws.s3.S3FileIO`, `AWS_REGION`,
  `JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=50` and a 512 MiB limit: healthy in a few seconds,
  about 70 MiB in use, `catalog.db` created in the volume.
- `GET /v1/config` returns `"defaults":{}` and `"overrides":{}`: the fixture gives no S3
  setting to clients. Spark uses its own environment (`AWS_REGION`, instance profile).

## Conventions for every task

- All file content, comments, commit messages: English.
- Commit messages: Conventional Commits style, **no `Co-Authored-By` line** and no Claude
  attribution (`CLAUDE.md`).
- Do not push. The controller pushes the batch and opens the PR.
- Never write a real account ID, bucket name, ARN, external ID, password or secret into a
  tracked file. `.env` holds real values: never print it, never commit it.
- `.env` exception: the implementer may set the one line `COMPOSE_PROFILES=...` with `sed`.
  This line holds no secret. Never print other lines. At the end of the task, set it back to
  `COMPOSE_PROFILES=` (empty, the user's value) and run `make up`.
- Prefer `COMPOSE_PROFILES=<x>` in the shell over a change to `.env`: Compose, `make up` and the
  tests read the shell value first.
- `secrets/` is git-ignored. Never print `secrets/spark_user.env`.
- Never run `aws/setup.sh` or `aws/teardown.sh`, and never change an AWS resource. The `aws`
  CLI runs only inside the `spark` container, as part of a test.
- The VM role **cannot delete** under `polaris/`. If an object is left under `polaris/`, report
  its exact key (bucket redacted as `<bucket>`): the user deletes it from CloudShell.
- No `${VAR:?}` in `docker-compose.yml`: `make lint` renders the file against `.env.example`.
- In this shell `cat` is an alias for a missing `bat`: use `command cat` or the Write tool.
- Do not run `make reset` or `docker compose down -v` (they delete the volumes).
- Branch: `phase4-baseline` (already checked out).

## File map

| File | Responsibility | Task |
|---|---|---|
| `docker-compose.yml` | Service `rest-fixture` (profile `baseline`), volume `rest-fixture-data`, `spark` optional dependency | 18 |
| `spark/conf/catalogs/baseline.conf` | Spark catalog `rest` | 18 |
| `.env.example` | `COMPOSE_PROFILES` comment lists `baseline` | 18 |
| `Makefile` | `sql-rest` | 18 |
| `tests/catalog-selection.sh` | `COMPOSE_PROFILES=baseline` adds `rest-fixture` | 18 |
| `tests/spark-config.sh` | `rest` block only with `baseline` | 18 |
| `tests/catalog-smoke.sh` | `rest` case: `DROP TABLE ... PURGE`, no file left | 19 |
| `tests/smoke-test.sh` | Map service → Spark catalog | 19 |
| `NOTES.md`, `README.md`, `docs/HANDOFF.md` | Findings, status, access table, handoff | 20 |

---

## Task 18: `rest-fixture` service and Spark catalog `rest`

**Files:**
- Modify: `docker-compose.yml`
- Create: `spark/conf/catalogs/baseline.conf`
- Modify: `.env.example` (comment of `COMPOSE_PROFILES`)
- Modify: `Makefile`
- Test: `tests/catalog-selection.sh`, `tests/spark-config.sh`

- [ ] **Step 1: Write the failing tests**

In `tests/catalog-selection.sh`, after the line that checks `COMPOSE_PROFILES=polaris`, add:

```bash
assert_eq "$(services baseline)" "postgres,rest-fixture,spark" "COMPOSE_PROFILES=baseline adds rest-fixture"
```

In `tests/spark-config.sh`, after the line
`assert_not_contains "$none" "spark.sql.catalog.nessie" "no nessie block with no catalog"`, add:

```bash
assert_not_contains "$none" "spark.sql.catalog.rest" "no rest block with no catalog"
```

and before the final `finish`, add:

```bash
rest=$(conf baseline)
assert_contains "$rest" "spark.sql.catalog.rest.uri    http://rest-fixture:8181" "rest block with baseline"
assert_not_contains "$(conf nessie)" "spark.sql.catalog.rest" "no rest block with nessie only"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `tests/catalog-selection.sh; echo "exit=$?"`
Expected: `FAIL - COMPOSE_PROFILES=baseline adds rest-fixture (expected 'postgres,rest-fixture,spark', got 'postgres,spark')`, `exit=1`.
The script runs `make up` at the end; the stack returns to the `.env` selection.

Run: `tests/spark-config.sh; echo "exit=$?"`
Expected: `FAIL - rest block with baseline (missing ...)`, `exit=1`.

- [ ] **Step 3: Add the service and the volume**

In `docker-compose.yml`, add this service after the `nessie` service (before `polaris-bootstrap`):

```yaml
  rest-fixture:
    image: ${REST_FIXTURE_IMAGE}
    # Catalogs are off by default; COMPOSE_PROFILES in .env selects them (spec section 5.0).
    profiles: [baseline]
    environment:
      # JDBC catalog on a SQLite file in a volume: the catalog survives a restart.
      # The volume is the home of the image user iceberg, so iceberg can write it.
      CATALOG_URI: jdbc:sqlite:/home/iceberg/catalog.db
      CATALOG_WAREHOUSE: s3://${S3_BUCKET}/rest/
      CATALOG_IO__IMPL: org.apache.iceberg.aws.s3.S3FileIO
      # AWS default credential chain: the VM instance profile through IMDSv2.
      AWS_REGION: ${AWS_REGION}
      # Optional static keys: empty on AWS, the default chain then falls through to the instance profile.
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:-}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:-}
      JAVA_TOOL_OPTIONS: -XX:MaxRAMPercentage=50
    mem_limit: 512m
    volumes:
      - rest-fixture-data:/home/iceberg
    ports:
      # The fixture listens on 8181, the host port of Polaris: use 8183 on the host (spec section 5.4).
      - "127.0.0.1:8183:8181"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8181/v1/config >/dev/null"]
      interval: 5s
      timeout: 5s
      retries: 30
```

At the end of the file, replace

```yaml
volumes:
  pgdata:
```

with

```yaml
volumes:
  pgdata:
  rest-fixture-data:
```

In the `spark` service, in `depends_on`, after the `polaris-setup` entry, add:

```yaml
      rest-fixture:
        condition: service_healthy
        required: false
```

- [ ] **Step 4: Add the Spark template**

Create `spark/conf/catalogs/baseline.conf`:

```
# Catalog rest (profile baseline): apache/iceberg-rest-fixture, the reference catalog of the
# Iceberg quickstart. Spark writes the data files with the VM instance profile.
spark.sql.catalog.rest        org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.rest.type   rest
spark.sql.catalog.rest.uri    http://rest-fixture:8181
```

- [ ] **Step 5: Update `.env.example` and the Makefile**

In `.env.example`, replace

```
# Catalogs to start, comma-separated, no spaces: nessie, polaris. Empty = no catalog (default).
```

with

```
# Catalogs to start, comma-separated, no spaces: nessie, polaris, baseline (Spark catalog rest).
# Empty = no catalog (default).
```

In `Makefile`, add `sql-rest` to the `.PHONY` line, and after the `sql-polaris` target add:

```make
sql-rest:
	docker compose exec spark spark-sql --conf spark.sql.defaultCatalog=rest
```

(The recipe line starts with a tab.)

- [ ] **Step 6: Rebuild the Spark image and run the tests**

The Dockerfile copies the templates into the image, so rebuild it first.

Run: `docker compose build spark`
Expected: the build ends without error.

Run: `make lint`
Expected: `lint passed`, then the secret check passes.

Run: `tests/spark-config.sh; echo "exit=$?"`
Expected: `all assertions passed`, `exit=0`.

Run: `tests/catalog-selection.sh; echo "exit=$?"`
Expected: `all assertions passed`, `exit=0`.

- [ ] **Step 7: Start the baseline and check it from Spark**

Run: `COMPOSE_PROFILES=baseline make up`
Expected: `rest-fixture`, `postgres` and `spark` are healthy.

Run: `docker compose ps --status running --services | sort | paste -sd, -` (with
`COMPOSE_PROFILES=baseline` in the shell)
Expected: `postgres,rest-fixture,spark`.

Run: `docker compose exec -T spark spark-sql -S -e "CREATE NAMESPACE IF NOT EXISTS rest.smoke; SHOW NAMESPACES IN rest;" 2>/dev/null`
Expected: the output has the line `smoke`.

Run: `docker compose exec -T rest-fixture ls -l /home/iceberg/catalog.db`
Expected: the file exists and belongs to `iceberg`.

Then go back to the `.env` selection: `make up` (no shell variable). Expected: `rest-fixture`
is stopped; the volume `rest-fixture-data` stays.

- [ ] **Step 8: Commit**

```bash
git add docker-compose.yml spark/conf/catalogs/baseline.conf .env.example Makefile tests/catalog-selection.sh tests/spark-config.sh
git commit -m "feat(baseline): add the rest-fixture catalog behind the baseline profile"
```

---

## Task 19: Catalog acceptance test on `rest`

**Files:**
- Modify: `tests/catalog-smoke.sh`
- Modify: `tests/smoke-test.sh`

- [ ] **Step 1: Run the test to verify it fails**

Run: `tests/catalog-smoke.sh rest; echo "exit=$?"`
Expected: `unknown catalog 'rest'; usage: ...` and `exit=2`.

- [ ] **Step 2: Add the `rest` case**

In `tests/catalog-smoke.sh`, replace the `case` block and its comment lines with:

```bash
# Per-catalog policy.
# own_files=1: the VM role can delete under the prefix. It deletes the table files after the
# drop (Nessie never deletes files) or the files that a purge leaves.
# own_files=0: DROP TABLE ... PURGE deletes the files with the credentials that the catalog
# vends; the VM role cannot write under polaris/.
# A drop with PURGE must leave no file under the table root.
case $catalog in
  nessie) prefix=nessie; drop_sql="DROP TABLE IF EXISTS %s"; own_files=1 ;;
  polaris) prefix=polaris; drop_sql="DROP TABLE IF EXISTS %s PURGE"; own_files=0 ;;
  rest) prefix=rest; drop_sql="DROP TABLE IF EXISTS %s PURGE"; own_files=1 ;;
  *) echo "unknown catalog '$catalog'; usage: tests/catalog-smoke.sh nessie|polaris|rest" >&2; exit 2 ;;
esac
```

- [ ] **Step 3: Check every purge, and delete what a purge leaves when the VM role can**

In the `cleanup` function, replace this block:

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

with:

```bash
  if [[ -n $root && $drop_sql == *PURGE ]]; then
    left=$(docker compose exec -T spark aws s3 ls --recursive "$root/" 2>/dev/null || true)
    if [[ -n $left ]]; then
      echo "  FAIL - files left under $root/ after the purge:"
      echo "$left"
      if ((own_files)); then
        docker compose exec -T spark aws s3 rm --recursive --quiet "$root/" >/dev/null 2>&1 \
          || echo "  warn - could not delete $root/"
      fi
      exit 1
    fi
  elif ((own_files)) && [[ -n $root ]]; then
```

The rest of `cleanup` stays as it is. Check the result: the `polaris` case behaves as before
(PURGE, `own_files=0`), the `nessie` case behaves as before (no PURGE, the VM role deletes).

- [ ] **Step 4: Map each service to its Spark catalog in `tests/smoke-test.sh`**

Replace the loop

```bash
for catalog in nessie polaris; do
  if grep -qx "$catalog" <<<"$services"; then
    "tests/$catalog-service.sh"
    tests/catalog-smoke.sh "$catalog"
    ran=1
  fi
done
```

with:

```bash
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
```

- [ ] **Step 5: Run the acceptance test on `rest`**

Run: `COMPOSE_PROFILES=baseline make up`
Expected: `postgres`, `rest-fixture` and `spark` are healthy.

Run: `COMPOSE_PROFILES=baseline make smoke-test; echo "exit=$?"`
Expected: the base tests pass, then `catalog rest` with every line `ok`: table created and
read, data file under the `rest/` prefix, `aws s3 ls` shows `.parquet` and `.metadata.json`,
stack restart, rows read again, `all assertions passed`. No `files left` line. `exit=0`.

Then check that the purge removed the files of the table. Take the table name from the
output (`t_<timestamp>`) and run:
`docker compose exec -T spark aws s3 ls --recursive s3://$(docker compose exec -T spark printenv S3_BUCKET | tr -d '\r')/rest/smoke/ | grep t_<timestamp> || echo "no file left"`
Expected: `no file left`.

Record for Task 20 who deleted the files (Spark or the fixture). Look in the fixture log:
`docker compose logs --no-color rest-fixture | grep -iE "purg|drop" | tail -n 5`.
Report what the log shows; do not guess.

If a step fails, use `superpowers:systematic-debugging`; do not change the test to make it pass.

- [ ] **Step 6: Run the regression on the other catalogs**

Run: `COMPOSE_PROFILES=nessie make up`, then `COMPOSE_PROFILES=nessie make smoke-test; echo "exit=$?"`
Expected: `catalog nessie` with every line `ok`, `exit=0`.

Run: `COMPOSE_PROFILES=polaris make up`, then `COMPOSE_PROFILES=polaris make smoke-test; echo "exit=$?"`
Expected: `catalog polaris` with every line `ok`, no `files left` line, `exit=0`.

Then go back to the `.env` selection: `make up`. Run `make lint`: `lint passed`.

- [ ] **Step 7: Commit**

```bash
git add tests/catalog-smoke.sh tests/smoke-test.sh
git commit -m "test(baseline): run the catalog acceptance test on rest"
```

---

## Task 20: Notes, README and handoff

**Files:**
- Modify: `NOTES.md`
- Modify: `README.md`
- Modify: `docs/HANDOFF.md`

- [ ] **Step 1: `NOTES.md`**

In the section "Findings", after F4, add (replace `<who purges>` with what Task 19 Step 5
observed: "Spark deletes the files" or "the fixture deletes the files on the server", with the
log evidence):

```markdown
### F5 — `apache/iceberg-rest-fixture` (1.10.1, checked 2026-10-29)
- No tag matches Iceberg 1.11: the lab uses 1.10.1, the newest versioned tag. The Spark client
  is 1.11.0. The acceptance test passes with this combination.
- The default catalog is SQLite on `/tmp/iceberg_catalog.db`, which is lost when the container
  is recreated. Lab: `CATALOG_URI=jdbc:sqlite:/home/iceberg/catalog.db` on the named volume
  `rest-fixture-data`. The volume is mounted on `/home/iceberg`, the home of the image user
  `iceberg` (uid 1000): Docker gives a named volume the owner of the folder in the image. A
  folder that is not in the image (for example `/home/iceberg/data`) is owned by root, and the
  fixture cannot write it.
- The fixture listens on 8181, the host port of Polaris. Lab: host port 8183, so `polaris` and
  `baseline` can be on together.
- `GET /v1/config` gives no default to clients (`"defaults":{}`): Spark uses its own region
  (`AWS_REGION`) and the VM instance profile.
- `DROP TABLE ... PURGE`: <who purges>. `tests/catalog-smoke.sh rest` fails when a file is left
  under the table root, and the VM role deletes it.
- On-premise S3 for the fixture (`CATALOG_S3_ENDPOINT`, path-style access): not configured and
  not tested. An empty endpoint value can break `S3FileIO`, so the lab does not pass it on AWS.
```

In the section "Open investigations", delete the line
``- `apache/iceberg-rest-fixture`: no tag matches Iceberg 1.11; the lab uses 1.10.1.``
(F5 covers it), and replace "Filled in during phases 2-4." with "Filled in during the later
phases."

In D11, replace ``(`polaris`, `nessie`, later `baseline`)`` with ``(`polaris`, `nessie`, `baseline`)``.

- [ ] **Step 2: `README.md`**

Make these changes:

1. "Status": Phase 4 (baseline) is done. Write: "Stage 1 (AWS scripts), Phase 1 (Postgres,
   Spark image), Phase 2 (Polaris), Phase 3 (Nessie) and Phase 4 (baseline catalog `rest`) are
   done. The scenario notebooks (Phase 5) and the evaluation (Phase 6) are not done yet."
2. Catalog table: in the `rest` row, replace `(Phase 4, Compose profile `baseline`)` with
   `(Compose profile `baseline`)`.
3. Mermaid diagram: replace `jupyter -. Iceberg REST .-> rest` with
   `jupyter -- Iceberg REST --> rest`, replace `jupyter -. instance profile .-> r` with
   `jupyter -- instance profile --> r`, and after `nessie -- instance profile --> n` add
   `rest -- instance profile --> r`. Add `rest --> rfv[(SQLite volume)]` inside the `vm`
   subgraph, after `nessie --> pg`.
4. "Choose the catalogs", step 1: "Set `COMPOSE_PROFILES` in `.env`: `polaris`, `nessie`,
   `baseline` (Spark catalog `rest`), or a list (`nessie,polaris`, no spaces). Leave it empty
   for no catalog."
5. "Daily use": "**Spark SQL shell**: `make sql-polaris`, `make sql-nessie` or `make sql-rest`."
   After the Polaris `PURGE` item, add: "- **Drop a baseline table with its files**:
   `DROP TABLE rest.<namespace>.<table> PURGE`."
6. "Make targets": replace the `make sql-polaris`, `make sql-nessie` row with
   ``| `make sql-polaris`, `make sql-nessie`, `make sql-rest` | Opens a Spark SQL shell on the catalog |``.
   In the `make reset` row write: "Like `make down`, and also **deletes the volumes**: all
   Polaris and Nessie metadata (Postgres) and the baseline catalog (SQLite) are lost. The S3
   files stay".
7. "Access from your machine" table: after the Polaris management row, add
   ``| Baseline REST catalog (no authentication) | 8183 | <http://localhost:8183/v1/config> |``.
   In the first sentence, replace "Nessie and the Spark UI have no authentication" with
   "Nessie, the baseline catalog and the Spark UI have no authentication".
8. SSH tunnel command: after `-L 8182:127.0.0.1:8182 \` add `-L 8183:127.0.0.1:8183 \`.
9. SSM step 2: "(4040, 19120, 9000, 8181, 8182, 8183)".
10. "On-premise S3 storage": after "the Nessie management port 9000 is also the default MinIO
    port" add ", and the baseline catalog has no S3 endpoint setting yet".
11. "Documents" table: after the Phase 2 plan row, add
    ``| [Plan: Phase 4 (baseline)](docs/superpowers/plans/2026-10-29-phase4-baseline.md) | Task-by-task implementation plan |``.

- [ ] **Step 3: `docs/HANDOFF.md`**

Update the handoff for the next session:
- "Where we are": add the row ``| Plan (Phase 4) | `docs/superpowers/plans/2026-10-29-phase4-baseline.md` — Tasks 18-20 |``,
  add the Phase 4 issue numbers to the issues row, add the row
  ``| Phase 4 (baseline) | PR open (branch `phase4-baseline`) |`` and set "Next step" to
  "After the merge of the Phase 4 PR: write the Phase 5 plan (scenarios)".
- "Resume here": replace with the Phase 4 PR state and the Phase 5 start (brainstorm, plan,
  issues, subagent-driven execution; read the code, not the old plans).
- "State of the VM": add that the volume `rest-fixture-data` holds the baseline catalog, and
  that the `rest` catalog holds the empty namespace `smoke`.
- "Rules for work on the VM": the `make reset` line also deletes the `rest-fixture-data` volume.
- "Open points to watch": remove the two Phase 4 items (smoke-test map, fixture tag); keep the
  others.

- [ ] **Step 4: Check and commit**

Run: `make lint`
Expected: `lint passed`, then the secret check passes.

```bash
git add NOTES.md README.md docs/HANDOFF.md
git commit -m "docs(baseline): record the Phase 4 findings and usage"
```

---

## Out of scope for this plan

- On-premise S3 for the fixture (`CATALOG_S3_ENDPOINT`, path-style access, static keys test).
- Authentication on the fixture (it has none; ports stay on `127.0.0.1`).
- Phase 5 scenarios on the `rest` catalog.
- The Nessie CLI (issue #22).
