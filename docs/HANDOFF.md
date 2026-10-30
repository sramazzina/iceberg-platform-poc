# Handoff — Iceberg catalog lab

- Date: 2026-10-30
- From: Claude Code session on the user's workstation (Windows, WSL2, Docker Desktop):
  Tasks 24-28 of the on-premise variant with RustFS, final review, push and PR
- To: the next Claude Code session on the **same workstation** (or on the EC2 VM for the
  AWS regression)

## Where we are

| Item | State |
|---|---|
| Requirements | `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` (Italian) |
| Lab design spec | `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md` |
| Stage 1, Phases 1-4, Nessie CLI | Merged (PRs #10, #11, #16, #23, #27, #30, #32) |
| Phase 5 (scenarios), Phase 6 (evaluation) | Deferred (`NOTES.md` D14) |
| **On-premise variant with RustFS** | **Implementation complete**, PR **#39** open (branch `feat/rustfs-onprem`, pushed) |
| RustFS spec | `docs/superpowers/specs/2026-10-29-rustfs-onprem-design.md` (on the branch) |
| RustFS plan | `docs/superpowers/plans/2026-10-29-rustfs-onprem.md` (on the branch) — Tasks 23-28 |
| GitHub issues | #33-#38, all closed by PR #39 on merge. All checklists ticked, except one item of #37: the AWS regression |
| Final review of the branch | Done ("ready with minor fixes"); fixes in `434127c` |

Commits on `feat/rustfs-onprem`: spec `f7f1f5d`, plan `02c8a4d` and `36c603d`, T23 `321deeb`
and `dcfea72`, T24 `dae348c`, T25 `7c847d2`, T26 `bdbe305`, T27 `d52ecc3`, T28 `8d2f0c3`,
final review fixes `434127c`.

Findings of the execution (recorded in `NOTES.md` F6 on the branch):
- RustFS accepts only S3 ARNs as policy resources. The `sts:AssumeRole` statement of
  `rustfs/setup/policy-polaris.json` has no `Resource`; AssumeRole works with it.
- Polaris adds a KMS statement to the session policy, and RustFS rejects it.
  `polaris/setup/setup.sh` sets `kmsUnavailable: true` only when `S3_ENDPOINT` is set.
- Nessie 0.109.0 gives `s3.path-style-access` to clients: no Nessie fallback template.

## Resume here

1. **First thing in the next session:** show the user (in Italian) the commands below for the
   AWS regression (plan, Task 27 Step 3), then wait for the result. The user runs them on the
   EC2 VM, in the repository directory; Claude does not run them (no AWS on the workstation).

   ```bash
   git fetch origin
   git checkout feat/rustfs-onprem
   git pull
   tests/catalog-selection.sh
   COMPOSE_PROFILES=nessie,polaris,baseline make up
   COMPOSE_PROFILES=nessie,polaris,baseline make smoke-test
   tests/spark-config.sh
   make lint
   make up   # back to the .env selection (postgres and spark only)
   ```

   Expected: all green, no `FAIL`. No object is left under `polaris/` on AWS (the smoke test
   checks it). The VM `.env` does not need the RustFS lines (`make lint` renders against
   `.env.example`). If a test fails, ask the user for the output of the failing command.
2. If the regression passes: tick the third item of issue #37 and update the PR #39 test
   plan. If it fails: fix on the branch (collect the fixes, push them as one batch).
3. Check the CI of PR #39. The user merges; never merge yourself.
4. After the user confirms the merge: delete the branch locally and on the remote,
   `git checkout main && git pull`, then update this file.

## State of this workstation

- Windows, WSL2 (kernel `6.18.33.2-microsoft-standard-WSL2`), Docker Desktop 29.9.2,
  20 CPUs, 32 GB. No AWS credentials, no AWS stack.
- The workstation shut down unexpectedly on 2026-10-30. After a restart, start Docker
  Desktop (WSL integration) before any `docker` or `make` command.
- `.env` is a **local** file for the RustFS variant: `COMPOSE_FILE=docker-compose.yml:docker-compose.rustfs.yml`,
  `S3_BUCKET=iceberg-lab`, `COMPOSE_PROFILES=` (no catalog), random local passwords and
  keys, no AWS value. Claude may change its lines; never print it.
- Last state of the variant: `postgres`, `rustfs`, `spark`. The bucket, the users `polaris`
  and `lab`, `lab_catalog` and `secrets/rustfs/spark_user.env` exist. The catalogs hold no
  table (only the empty namespace `smoke`).
- `data/rustfs/` and `secrets/rustfs/` exist (git-ignored on the branch). On `main`, `data/`
  shows as untracked.
- Docker volumes: `pgdata-rustfs`, `rest-fixture-data-rustfs` (variant) and `pgdata` (one
  switch test to the AWS configuration; empty catalogs).

## State of the EC2 VM (unchanged since the previous handoff)

- The AWS stack runs there with `postgres` and `spark` only (`COMPOSE_PROFILES=`).
- `secrets/spark_user.env` exists there. Catalogs: only the empty namespace `smoke`. The S3
  bucket has no object under `polaris/`, `nessie/` or `rest/`.
- The VM role can only **list** under `polaris/`: drop every Polaris table with
  `DROP TABLE ... PURGE`; a left file must be deleted by the user from CloudShell.
- For the AWS regression of Task 27: the VM `.env` needs the new RustFS lines of
  `.env.example` only if the variant runs there; the AWS stack does not need them, but
  `make lint` renders against `.env.example`, so it works without them.

## Decisions already taken with the user (do not ask again)

1. Repository root = this repository. The repository is **public**: no account ID, ARN,
   bucket name, external ID, password or secret in any tracked file.
2. AWS: `aws/setup.sh` and `aws/teardown.sh` are run by the user in AWS CloudShell. Claude
   never creates or changes AWS resources.
3. Spark image `apache/spark:4.1.3-scala2.13-java17-python3-ubuntu`, Python 3.10; Iceberg
   client 1.11.0; versions in `VERSIONS.md`.
4. The catalogs are off by default; `COMPOSE_PROFILES` in `.env` selects them (`NOTES.md` D11).
5. The Nessie CLI is in the `spark` image (`make nessie-cli`).
6. Phases 5 and 6 are deferred (`NOTES.md` D14).
7. **On-premise storage = RustFS 1.0.4** (Apache-2.0), not MinIO (archived, AGPLv3), not
   Versity S3 Gateway (no STS). RustFS keeps objects in an internal format; the user accepts
   it, because the web console shows the storage (2026-10-29).
8. The variant targets Linux, macOS and Windows (WSL2) hosts. Data directory = bind mount
   `RUSTFS_DATA_DIR` (default `./data/rustfs`).
9. The variant is a Compose override file `docker-compose.rustfs.yml`, selected with
   `COMPOSE_FILE` in `.env`. The AWS stack stays the default and does not change.
10. Credentials: dedicated RustFS users, as the AWS model. `polaris` (STS caller, `polaris/`),
    `lab` (Spark, Nessie, `rest`: `nessie/` and `rest/`, only list on `polaris/`). Root only
    for `rustfs-setup` and the console. Polaris vends credentials through the RustFS STS; do
    not use `stsUnavailable`.
11. Verification: Claude verifies on this workstation (counts as Windows WSL2 + Docker
    Desktop). The user runs the AWS regression on the EC2 VM before the merge. Other hosts
    are documented as not verified.
12. One plan, one branch, one PR for Tasks 23-28; one commit per task plus review-fix commits.

## How to execute (from `CLAUDE.md` and `~/.claude/CLAUDE.md`)

- Execute the plan with `superpowers:subagent-driven-development`. Do not ask for an
  execution mode.
- Implementer and fact-finding subagents: `model: "sonnet"`. Reviews, synthesis and
  documentation stay with the main model.
- Commit messages, PR bodies and issues: English, Conventional Commits, **no `Co-Authored-By`
  line and no Claude attribution**.
- Do not push after every commit. Push the batch when the PR is ready; open the PR last. The
  user merges; never merge yourself. After the merge: delete the branch locally and on the
  remote, then `git checkout main && git pull`.
- Chat with the user in Italian; every file, commit, issue and PR in English. Documentation
  follows ASD-STE100.

## Rules for work on this workstation

- Never print `.env`, `secrets/spark_user.env` or `secrets/rustfs/spark_user.env`.
- Do not run `make reset` or `docker compose down -v` without the user's approval.
- In this shell `cat` is an alias for a missing `bat`: use `command cat` or the Write tool.
- The shell cwd resets to `docs/` after each command: use absolute paths.

## Open points to watch

- `rustfs-setup` is verified only for a second run with the same values. A change of a
  `RUSTFS_*_KEY` value or of `S3_BUCKET` is not verified (README, "Data directory").
- The variant is not verified on Linux with Docker Engine and on macOS.
- The RustFS log warns that it cannot write `/logs` when it runs as `LAB_UID`; it logs to
  stdout. Harmless.
- From the AWS work: Nessie management port `127.0.0.1:9000` (RustFS uses host ports
  9100/9101 for this reason); deferred pinning of transitive pip dependencies and the GPG
  check of the AWS CLI archive.

## Kick-off prompt for the next session

```text
Read docs/HANDOFF.md (on main). PR #39 (RustFS variant) is open. Follow "Resume here":
show me the AWS regression commands for the EC2 VM, then wait for my result.
```
