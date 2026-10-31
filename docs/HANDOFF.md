# Handoff — Iceberg catalog lab

- Date: 2026-10-31
- From: Claude Code session on the user's workstation (Windows, WSL2, Docker Desktop):
  ELT pipeline with dbt, Task 32 done
- To: the next Claude Code session on the **same workstation**

## Where we are

| Item | State |
|---|---|
| Requirements | `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` (Italian) |
| Lab design spec | `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md` |
| Stage 1, Phases 1-4, Nessie CLI, RustFS variant | Merged (PRs #10, #11, #16, #23, #27, #30, #32, #39) |
| Phase 5 (scenarios), Phase 6 (evaluation) | Deferred (`NOTES.md` D14) |
| **ELT with dbt** | **In progress** on branch `feat/dbt-elt` (local only, **not pushed**, no PR) |
| dbt spec | `docs/superpowers/specs/2026-10-30-dbt-elt-design.md` (section 4.1: spike results and design changes) |
| dbt plan | `docs/superpowers/plans/2026-10-30-dbt-elt.md` — Tasks 29-36 |
| GitHub issues | #40 (T29) … #47 (T36). #41, #42, #43 all ticked. #40 all ticked except "Spike objects removed" (see below) |
| CI | The repository has no GitHub Actions workflow |

Commits on `feat/dbt-elt` (after `47112d6` of `main`):

| Commit | Task | Review |
|---|---|---|
| `1afc946`, `7a41020`, `d35ad92` | Spec and plan | Approved by the user |
| `a5f341a` | T29 spike, `NOTES.md` F7 | Done |
| `3da9d1a` | Spike results applied to spec and plan | — |
| `8a04cb8`, `44677c6` | T30 Python packages of the `spark` image; license note in `VERSIONS.md` | Spec and quality review approved |
| `9915a82` | T31 service `spark-thrift` (profile `thrift`) | Spec and quality review approved (minor notes only) |
| `bfba70c` | T32 TPC-H generation, load and clean (`elt/`, `tests/tpch.sh`) | Spec review approved (identical to the plan) |
| `875ed37` | T32 quality review fixes: S3 listing errors detected, clean guard on the namespace prefix, typed `UNTIL` date, finite `SF`, stricter test checks | Re-review approved; `tests/tpch.sh` passed on nessie, polaris and rest |

Spike results (`NOTES.md` F7), already applied to the plan text of Tasks 32-35:
- Thrift Server authentication `NOSASL`. JDBC URL `jdbc:hive2://…:10000/;auth=noSasl`; dbt
  targets have `auth: NOSASL`; PyHive `auth="NOSASL"`.
- The key `set:hiveconf:spark.sql.defaultCatalog` in `server_side_parameters` selects the
  catalog. PyHive opens the session with `USE default`: `make dbt` creates
  `<catalog>.default` first.
- Staging models are **tables**, not views: Polaris does not delete the metadata file of a
  dropped view.
- Target `rest` has `threads: 1`: `rest-fixture` (SQLite) locks under concurrent commits
  (`SQLITE_BUSY`; fix: `docker compose restart rest-fixture`).
- Nessie shows only the snapshot of its current commit: tests check the operation of the
  last snapshot (`append`, then `overwrite`), not a snapshot count.
- The DuckDB `tpch` extension is installed at image build time.

User decision (2026-10-30): `text-unidecode` 1.3 (from `dbt-core`, dual license Artistic or
GPLv2+) is accepted under the Artistic License (`VERSIONS.md`).

## Resume here

1. `git checkout feat/dbt-elt`. Start Docker Desktop (WSL integration) and check with
   `docker info`.
2. Continue the plan with `superpowers:subagent-driven-development` from **Task 33** (issue
   #44): one implementer subagent per task (`model: "sonnet"`), then a spec review and a
   code quality review. Tick each issue checklist after the task.
   - **Correction to the plan commands (Tasks 33, 34, 36):** the form
     `COMPOSE_PROFILES=... make up && tests/<test>.sh` is wrong. The test then runs with the
     empty `COMPOSE_PROFILES` of `.env`: `tests/tpch.sh` reports "catalog is off", and
     `tests/dbt-project.sh` skips every catalog and passes without a check. Export the value
     for the test: `export COMPOSE_PROFILES=nessie,polaris,baseline,thrift; make up;
     tests/dbt-project.sh`. Restore with `unset COMPOSE_PROFILES; make up`.
   - `tests/tpch.sh` takes 5-10 minutes per catalog (many JVM starts). Run the catalogs
     one after the other, never in parallel.
   - Task 32 changed `elt/tpch_clean.py` after the plan text: the location guard is now the
     namespace prefix `s3://<bucket>/<catalog>/<namespace>/`, and the table is not dropped
     when the guard fails. Tasks 33-34 must not give dbt models an explicit `location`.
3. Tasks 33-36 remain. After Task 36: final review, push the branch, open one PR with
   `Closes #40` … `Closes #47`, give the user the AWS regression commands (Task 36) and ask
   for the DBeaver check.
4. Before the PR, close the last item of issue #40: one spike file is left on RustFS,
   `s3://iceberg-lab/polaris/spike_dbt/m_view/metadata/00000-….gz.metadata.json`. The user
   deletes it from the RustFS console (`http://localhost:9101`, prefix `polaris/spike_dbt/`).
   Claude may not read the RustFS keys from `.env` (the auto-mode classifier blocked it).

## Move to a Linux server (2026-10-31)

The user may continue on an always-on Linux server with Docker Engine instead of the
workstation. Branch `feat/dbt-elt` is pushed to `origin` (no CI runs: no workflow). On the
server:

- Clone the repository at the same path as the plan uses
  (`/home/sramazzina/work/dev/sramazzina/iceberg-platform-poc`), or replace the path in every
  plan command.
- `.env` is not tracked: the user creates it from `.env.example` for the RustFS variant
  (`COMPOSE_FILE=docker-compose.yml:docker-compose.rustfs.yml`, `S3_BUCKET=iceberg-lab`,
  `COMPOSE_PROFILES=` empty, local keys). Never print it.
- The `spark` image is not on the server: the first `make up` builds it (about 4 GB).
- The RustFS data of the workstation stays there: the server starts with an empty bucket.
  The spike file of issue #40 is then only on the workstation; the user deletes it there or
  drops the workstation RustFS data, then ticks the last item of #40.
- Open point: the RustFS variant is not verified on Linux with Docker Engine. Check the
  bind-mount ownership (`LAB_UID`) and `rustfs-setup` at the first `make up`.
- The workstation notes below (WSL2, `cat` alias) may not apply on the server.

## State of this workstation

- Windows, WSL2, Docker Desktop 29.9.2, 20 CPUs, 32 GB. No AWS credentials, no AWS stack.
- `.env` is a **local** file for the RustFS variant: `COMPOSE_FILE=docker-compose.yml:docker-compose.rustfs.yml`,
  `S3_BUCKET=iceberg-lab`, `COMPOSE_PROFILES=` (no catalog). Never print it.
- Running: `postgres`, `rustfs`, `spark` (image `iceberg-lab-spark:1.11.0` rebuilt with dbt and
  DuckDB, 4.1 GB). Start catalogs for one command with the shell, for example
  `COMPOSE_PROFILES=nessie,polaris,baseline,thrift make up`. `make up` alone stops them again.
- Catalogs: only the empty namespace `smoke`. No `spike_dbt` or `default` namespace is left.
- One smoke-test run of T31 failed once in the Polaris block (`secrets/spark_user.env`
  missing, client id expected empty); the second run passed. Cause not found; watch it.

## State of the EC2 VM

- The VM is still on the deleted branch `feat/rustfs-onprem`. At the next use there:
  `git checkout main && git pull`, then `git branch -D feat/rustfs-onprem`.
- The AWS stack runs there with `postgres` and `spark` only. Catalogs: only `smoke`.
- The VM role can only **list** under `polaris/`: drop every Polaris table with
  `DROP TABLE ... PURGE`; a left file must be deleted by the user from CloudShell.

## Decisions already taken with the user (do not ask again)

1. Repository root = this repository. The repository is **public**: no account ID, ARN,
   bucket name, external ID, password or secret in any tracked file.
2. AWS: the user runs `aws/setup.sh` and `aws/teardown.sh` in CloudShell. Claude never
   creates or changes AWS resources.
3. Spark image `apache/spark:4.1.3-scala2.13-java17-python3-ubuntu`, Python 3.10; Iceberg
   1.11.0; versions in `VERSIONS.md`.
4. The catalogs are off by default; `COMPOSE_PROFILES` in `.env` selects them (`NOTES.md` D11).
5. Phases 5 and 6 are deferred (`NOTES.md` D14).
6. On-premise storage = RustFS 1.0.4 (Apache-2.0) through `docker-compose.rustfs.yml`.
7. ELT (2026-10-30): one generic dbt project, one target per catalog; dbt-spark `thrift`
   method through a new Spark Thrift Server (also for DBeaver); TPC-H data generated with
   DuckDB in `landing/`, loaded by PySpark into `tpch_raw`; incremental model
   `fct_lineitem` (merge). One branch, one PR for Tasks 29-36.
8. Verification: Claude verifies on this workstation. The user runs the AWS regression on
   the EC2 VM before the merge.
9. TPC-H data (2026-10-31): the data loads only on demand, with `make tpch-gen` and
   `make tpch-load` (script `elt/tpch_load.py`). `make up` loads nothing. Only the tests load
   a small data set (`SF=0.01`) and drop it at the end. The user confirmed this design.
10. README (2026-10-31): the user asks for operational instructions in `README.md`. Task 35
   writes them. Make sure the procedure says that the data loads only on demand, and gives
   each step as one command.

## How to execute (from `CLAUDE.md` and `~/.claude/CLAUDE.md`)

- Subagent-driven execution; do not ask for an execution mode. Implementer and fact-finding
  subagents: `model: "sonnet"`. Reviews stay with the main model.
- Commit messages, PR bodies and issues: English, Conventional Commits, **no `Co-Authored-By`
  line and no Claude attribution**.
- Do not push after every commit. Push the batch when the PR is ready; open the PR last. The
  user merges; never merge yourself. After the merge: delete the branch locally and on the
  remote, then `git checkout main && git pull`.
- Chat with the user in Italian; every file, commit, issue and PR in English (ASD-STE100).

## Rules for work on this workstation

- Never print `.env`, `secrets/spark_user.env` or `secrets/rustfs/spark_user.env`.
- Do not run `make reset` or `docker compose down -v` without the user's approval.
- In this shell `cat` is an alias for a missing `bat`: use `command cat`.
- `gh pr edit` fails (Projects classic deprecation): use
  `gh api -X PATCH repos/sramazzina/iceberg-platform-poc/pulls/<n> -F body=@<file>`.
- Use absolute paths; the shell cwd can reset between commands.

## Open points to watch

- `rustfs-setup` is verified only for a second run with the same values.
- The RustFS variant is not verified on Linux with Docker Engine and on macOS.
- Deferred: pinning of transitive pip dependencies; GPG check of the AWS CLI archive; the
  DuckDB `tpch` extension download at build time has no checksum pin (DuckDB checks its
  signature).

## Kick-off prompt for the next session

```text
Read docs/HANDOFF.md (on main). Follow "Resume here": continue the dbt ELT plan on
branch feat/dbt-elt from Task 32.
```
