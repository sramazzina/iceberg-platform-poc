# Iceberg catalog lab — Nessie CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Nessie CLI to the `spark` image, with the command `nessie` and the target `make nessie-cli`, so the user can manage Nessie branches, tags, commits and merges from the command line (issue #22).

**Architecture:** `spark/Dockerfile` downloads the Nessie CLI uber jar from Maven Central, checks its pinned SHA-1, and puts it in `/opt/nessie-cli/` (not on the Spark classpath). A wrapper `/usr/local/bin/nessie` runs the jar and connects to `http://nessie:19120/api/v2` when no URI is given. The version and the checksum are pinned in `.env` and passed as build arguments.

**Tech Stack:** Nessie CLI 0.109.0 (Java uber jar, Apache-2.0), Java 17 of the `apache/spark` image, Docker Compose build arguments, Bash.

**Spec:** `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md`, section 5.0.1 and section 8.

---

## Facts verified on 2026-10-29 (on this VM)

- Maven Central: `https://repo1.maven.org/maven2/org/projectnessie/nessie/nessie-cli/0.109.0/nessie-cli-0.109.0.jar`,
  105546373 bytes, published SHA-1 `05c7b21afc3ee169966e36ff7fae4753ad8da8a3`.
- License: Apache-2.0 (POM of the parent `org.projectnessie.nessie:nessie:0.109.0`; image label
  `org.opencontainers.image.licenses=Apache-2.0`).
- The jar runs on the Java 17 of the `spark` image: `java -jar nessie-cli.jar --version` prints
  `0.109.0`.
- Options: `-u <uri>`, `-q` (no welcome and exit output), `--stdout` (standard streams, implies
  plain output; needed without a TTY), `-c <command>` (run and exit), `--no-up-to-date-check`.
- Against the lab Nessie: `-q --stdout -u http://nessie:19120/api/v2 -c "LIST REFERENCES"` prints
  connection lines, then ` BRANCH main @ <hash>`, exit 0.
- In the `spark` container: user `spark` (uid `LAB_UID`), `HOME=/workspace` (writable). The CLI
  writes its REPL history to `~/.nessie/`.

## Conventions for every task

- All file content, comments, commit messages: English (the requirements file
  `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` is Italian: keep it Italian).
- Commit messages: Conventional Commits style, **no `Co-Authored-By` line** and no Claude
  attribution (`CLAUDE.md`).
- Do not push. The controller pushes the batch and opens the PR.
- Never write a real account ID, bucket name, ARN, external ID, password or secret into a
  tracked file. `.env` holds real values: never print it, never commit it.
- `.env` exceptions: (1) the line `COMPOSE_PROFILES=...` (prefer `COMPOSE_PROFILES=<x>` in the
  shell); (2) Task 21 may append the two lines `NESSIE_CLI_VERSION=...` and
  `NESSIE_CLI_SHA1=...` when they are missing. They hold no secret. Never print other lines.
- `secrets/` is git-ignored. Never print `secrets/spark_user.env`.
- Never run `aws/setup.sh` or `aws/teardown.sh`, and never change an AWS resource.
- No `${VAR:?}` in `docker-compose.yml`: `make lint` renders the file against `.env.example`.
- In this shell `cat` is an alias for a missing `bat` (heredocs with `cat >` fail silently):
  use `command cat` or the Write tool.
- Do not run `make reset` or `docker compose down -v`.
- At the end of each task, run `make up` with no `COMPOSE_PROFILES` in the shell: the stack
  returns to the `.env` selection.
- Branch: `nessie-cli` (already checked out).

## File map

| File | Responsibility | Task |
|---|---|---|
| `.env.example` | `NESSIE_CLI_VERSION`, `NESSIE_CLI_SHA1` | 21 |
| `docker-compose.yml` | Build arguments of `spark` | 21 |
| `spark/Dockerfile` | Download and check the jar; install the wrapper | 21 |
| `spark/nessie-cli.sh` | Wrapper `nessie` (default URI, no up-to-date check) | 21 |
| `Makefile` | `nessie-cli` | 21 |
| `tests/spark-image.sh` | CLI version, not on the Spark classpath, same version as the server | 21 |
| `tests/nessie-service.sh` | The CLI in `spark` lists the branch `main` | 21 |
| `docs/req/...`, `README.md`, `VERSIONS.md`, `docs/HANDOFF.md` | Requirement, usage, versions, handoff | 22 |

---

## Task 21: Nessie CLI in the `spark` image

**Files:**
- Modify: `.env.example`, `docker-compose.yml`, `spark/Dockerfile`, `Makefile`
- Create: `spark/nessie-cli.sh`
- Test: `tests/spark-image.sh`, `tests/nessie-service.sh`

- [ ] **Step 1: Write the failing tests**

In `tests/spark-image.sh`, before `uid=$(run id -u)`, add:

```bash
assert_not_contains "$jars" "nessie-cli" "Nessie CLI jar not on the Spark classpath"
assert_eq "$(run nessie --version | tail -n1)" "$NESSIE_CLI_VERSION" "Nessie CLI pinned version"
assert_eq "$NESSIE_CLI_VERSION" "${NESSIE_IMAGE##*:}" "Nessie CLI version equals the Nessie server version"
```

In `tests/nessie-service.sh`, before `finish`, add:

```bash
refs=$(docker compose exec -T spark nessie -q --stdout -c "LIST REFERENCES" 2>&1 || echo "nessie CLI failed")
assert_contains "$refs" "BRANCH main @" "the Nessie CLI in the spark container lists the branch main"
```

- [ ] **Step 2: Add the pinned values**

In `.env.example`, after the line `NESSIE_IMAGE=ghcr.io/projectnessie/nessie:0.109.0`, add:

```
# Nessie CLI uber jar (Maven Central) in the spark image. Same version as NESSIE_IMAGE.
NESSIE_CLI_VERSION=0.109.0
NESSIE_CLI_SHA1=05c7b21afc3ee169966e36ff7fae4753ad8da8a3
```

Add the two values to `.env` only when they are missing, without printing `.env`:

```bash
grep -q '^NESSIE_CLI_VERSION=' .env || printf 'NESSIE_CLI_VERSION=0.109.0\n' >> .env
grep -q '^NESSIE_CLI_SHA1=' .env || printf 'NESSIE_CLI_SHA1=05c7b21afc3ee169966e36ff7fae4753ad8da8a3\n' >> .env
grep -c '^NESSIE_CLI_' .env
```

Expected: `2`.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `tests/spark-image.sh; echo "exit=$?"`
Expected: `FAIL - Nessie CLI pinned version (expected '0.109.0', got '... command failed ...')`
(the image has no `nessie` command yet), `exit=1`. The two other new lines pass.

- [ ] **Step 4: Write the wrapper**

Create `spark/nessie-cli.sh` and make it executable (`chmod 755 spark/nessie-cli.sh`):

```bash
#!/usr/bin/env bash
# Nessie CLI (installed as /usr/local/bin/nessie). Without -u/--uri it connects to the Nessie
# service of the lab. The up-to-date check is off: the lab does not call the internet.
set -euo pipefail

uri=(-u http://nessie:19120/api/v2)
for arg in "$@"; do
  case $arg in
    -u | --uri | -u=* | --uri=*) uri=() ;;
  esac
done

exec java -jar /opt/nessie-cli/nessie-cli.jar --no-up-to-date-check "${uri[@]}" "$@"
```

- [ ] **Step 5: Install the jar and the wrapper in the image**

In `spark/Dockerfile`, before the comment line
`# The spark user gets the host UID, so files saved in bind mounts stay editable on the host.`,
add:

```dockerfile
# Nessie CLI uber jar from Maven Central, checked against the pinned SHA-1. It stays out of
# the Spark classpath; the wrapper `nessie` runs it.
ARG NESSIE_CLI_VERSION
ARG NESSIE_CLI_SHA1
RUN set -eux; \
    mkdir -p /opt/nessie-cli; \
    curl -fsSLo /opt/nessie-cli/nessie-cli.jar \
      "https://repo1.maven.org/maven2/org/projectnessie/nessie/nessie-cli/${NESSIE_CLI_VERSION}/nessie-cli-${NESSIE_CLI_VERSION}.jar"; \
    echo "${NESSIE_CLI_SHA1}  /opt/nessie-cli/nessie-cli.jar" | sha1sum -c -
COPY nessie-cli.sh /usr/local/bin/nessie
```

In `docker-compose.yml`, in `spark.build.args`, after `AWSCLI_VERSION: ${AWSCLI_VERSION}`, add:

```yaml
        NESSIE_CLI_VERSION: ${NESSIE_CLI_VERSION}
        NESSIE_CLI_SHA1: ${NESSIE_CLI_SHA1}
```

- [ ] **Step 6: Add the Makefile target**

In `Makefile`, add `nessie-cli` to the `.PHONY` line, and after the `sql-rest` target add:

```make
nessie-cli:
	docker compose exec spark nessie
```

(The recipe line starts with a tab.)

- [ ] **Step 7: Rebuild the image and run the image test**

Run: `docker compose build spark`
Expected: the build ends without error; the log shows `/opt/nessie-cli/nessie-cli.jar: OK`.

Run: `tests/spark-image.sh; echo "exit=$?"`
Expected: `all assertions passed`, `exit=0`.

- [ ] **Step 8: Run the Nessie test with Nessie on**

Run: `COMPOSE_PROFILES=nessie make up`
Expected: `nessie`, `postgres` and `spark` are healthy (`make up` recreates `spark` with the
new image).

Run: `COMPOSE_PROFILES=nessie tests/nessie-service.sh; echo "exit=$?"`
Expected: every line `ok`, including `the Nessie CLI in the spark container lists the branch
main`, `exit=0`.

Run: `COMPOSE_PROFILES=nessie docker compose exec -T spark nessie -q --stdout -c "SHOW REFERENCE main"`
Expected: `Reference type: BRANCH` and `Name: main`.

Run: `COMPOSE_PROFILES=nessie docker compose exec -T spark nessie -q --stdout -u http://nessie:19120/api/v2 -c "LIST REFERENCES"`
Expected: ` BRANCH main @ ...` (an explicit `-u` works and is not doubled).

- [ ] **Step 9: Check and restore**

Run: `make up` (no shell variable). Expected: the stack returns to the `.env` selection.
Run: `make lint`. Expected: `lint passed`, then the secret check passes.

- [ ] **Step 10: Commit**

```bash
git add .env.example docker-compose.yml spark/Dockerfile spark/nessie-cli.sh Makefile tests/spark-image.sh tests/nessie-service.sh
git commit -m "feat(nessie): add the Nessie CLI to the spark image"
```

---

## Task 22: Requirements, README, versions and handoff

**Files:**
- Modify: `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` (Italian)
- Modify: `README.md`, `VERSIONS.md`, `docs/HANDOFF.md`

- [ ] **Step 1: Requirements (keep Italian)**

In `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md`, replace the line

```
Il laboratorio include anche la Nessie CLI, per usare l'API nativa di Nessie (branch, tag, commit, merge) dalla riga di comando. Questo requisito è per una fase successiva (issue #22): la progettazione e il piano vengono fatti in quella fase.
```

with

```
Il laboratorio include anche la Nessie CLI, per usare l'API nativa di Nessie (branch, tag, commit, merge) dalla riga di comando. La CLI è nell'immagine `spark` (comando `nessie`, target `make nessie-cli`). Issue #22.
```

In the same file, in the Makefile target list (the line that starts with "Il `Makefile` deve
avere almeno questi target"), add `nessie-cli` after `sql-nessie`.

- [ ] **Step 2: `README.md`**

1. "What the lab contains": after the sentence "`postgres` and `spark` always run. The
   catalogs are Compose profiles and are off by default.", add: "The `spark` image also has
   the Nessie CLI (command `nessie`)."
2. "Daily use": after the Spark SQL shell item, add:

   ```markdown
   - **Nessie CLI**: `make nessie-cli` (the catalog `nessie` must be on). The CLI is also in
     the JupyterLab terminal: run `nessie`. It connects to the Nessie service of the lab.
     Examples:

     ```text
     LIST REFERENCES;
     CREATE BRANCH dev FROM main;
     USE REFERENCE dev;
     SHOW LOG;
     MERGE dev INTO main;
     ```

     Without a terminal, run one command: `docker compose exec -T spark nessie -q --stdout -c "LIST REFERENCES"`.
     Documentation: <https://projectnessie.org/nessie-latest/cli/>.
   ```

   Before you commit, check each example in the running CLI (Step 3). If a syntax is
   different, write the syntax that works.
3. "Make targets": after the `make sql-...` row, add
   ``| `make nessie-cli` | Opens the Nessie CLI on the Nessie service (the catalog `nessie` must be on) |``.
4. "Documents" table: after the Phase 4 plan row, add
   ``| [Plan: Nessie CLI](docs/superpowers/plans/2026-10-29-nessie-cli.md) | Task-by-task implementation plan |``.

- [ ] **Step 3: Check the README examples**

Run: `COMPOSE_PROFILES=nessie make up`, then run each example with
`COMPOSE_PROFILES=nessie docker compose exec -T spark nessie -q --stdout -c "<command>"`, in
this order: `LIST REFERENCES`, `CREATE BRANCH dev FROM main`, `SHOW LOG main`,
`MERGE dev INTO main`, then remove the test branch with `DROP BRANCH dev`.
`USE REFERENCE dev` changes the state of a REPL session only: run it together with `SHOW LOG`
in one call (`-c "USE REFERENCE dev" -c "SHOW LOG"`).
Expected: every command ends without error, and `LIST REFERENCES` shows only `main` at the end.
If a command fails, read the CLI help (`-c "HELP"`) and fix the README example. Then run
`make up` with no shell variable.

- [ ] **Step 4: `VERSIONS.md`**

In the "Components" table, after the "Project Nessie" row, add:

```markdown
| Nessie CLI | 0.109.0 (uber jar in the `spark` image) | `NESSIE_CLI_VERSION`, `NESSIE_CLI_SHA1` | <https://repo1.maven.org/maven2/org/projectnessie/nessie/nessie-cli/0.109.0/> |
```

In the "Compatibility" table, add:

```markdown
| Nessie CLI 0.109.0 license and Java | Apache-2.0; runs on the Java 17 of the `spark` image (checked 2026-10-29) | <https://repo1.maven.org/maven2/org/projectnessie/nessie/nessie/0.109.0/nessie-0.109.0.pom> |
```

- [ ] **Step 5: `docs/HANDOFF.md`**

- "Where we are": add the row
  ``| Plan (Nessie CLI) | `docs/superpowers/plans/2026-10-29-nessie-cli.md` — Tasks 21-22 |``;
  in the issues row, write that #22 (Nessie CLI) closes with the Nessie CLI PR and add the new
  issue numbers; add the row ``| Nessie CLI | PR open (branch `nessie-cli`) |``; set "Next step"
  to "After the merge of the Nessie CLI PR: write the Phase 5 plan (scenarios)".
- "Resume here": the Nessie CLI PR is open, the user merges it; after the merge delete the
  branch locally and on the remote, then `git checkout main && git pull`; then Phase 5.
- "Decisions already taken": replace decision 12 with: "The Nessie CLI is in the `spark` image
  (command `nessie`, `make nessie-cli`), not in its own service (user decision, 2026-10-29)."
- "Open points to watch": add that `.env` on a VM set up before this change needs the two lines
  `NESSIE_CLI_VERSION` and `NESSIE_CLI_SHA1` (copy them from `.env.example`), otherwise the
  Spark build fails.

- [ ] **Step 6: Check and commit**

Run: `make lint`. Expected: `lint passed`, then the secret check passes.

```bash
git add docs/req/prompt-agente-lab-iceberg-polaris-nessie.md README.md VERSIONS.md docs/HANDOFF.md
git commit -m "docs(nessie): document the Nessie CLI"
```

---

## Out of scope for this plan

- Nessie CLI in its own container (`ghcr.io/projectnessie/nessie-cli`): not chosen.
- Nessie authentication for the CLI (Nessie runs without authentication, `NOTES.md` F2).
- Phase 5 scenarios that use the CLI.
