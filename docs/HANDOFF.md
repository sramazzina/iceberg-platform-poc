# Handoff — Iceberg catalog lab

- Date: 2026-10-30
- From: Claude Code session on the user's workstation (Windows, WSL2, Docker Desktop):
  AWS regression of the RustFS variant, merge of PR #39, cleanup
- To: the next Claude Code session on the **same workstation**

## Where we are

| Item | State |
|---|---|
| Requirements | `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` (Italian) |
| Lab design spec | `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md` |
| Stage 1, Phases 1-4, Nessie CLI | Merged (PRs #10, #11, #16, #23, #27, #30, #32) |
| Phase 5 (scenarios), Phase 6 (evaluation) | Deferred (`NOTES.md` D14) |
| **On-premise variant with RustFS** | **Merged** (PR #39, merge commit `b2c8dc9`, 2026-10-30). Branch `feat/rustfs-onprem` deleted (local and remote) |
| RustFS spec | `docs/superpowers/specs/2026-10-29-rustfs-onprem-design.md` |
| RustFS plan | `docs/superpowers/plans/2026-10-29-rustfs-onprem.md` — Tasks 23-28, all done |
| GitHub issues | #33-#38 closed, all checklists ticked |
| AWS regression (Task 27 Step 3) | Passed on the EC2 VM (run by the user, 2026-10-30) |
| CI | The repository has no GitHub Actions workflow (`.github/workflows` does not exist) |

Findings of the RustFS work (recorded in `NOTES.md` F6):
- RustFS accepts only S3 ARNs as policy resources. The `sts:AssumeRole` statement of
  `rustfs/setup/policy-polaris.json` has no `Resource`; AssumeRole works with it.
- Polaris adds a KMS statement to the session policy, and RustFS rejects it.
  `polaris/setup/setup.sh` sets `kmsUnavailable: true` only when `S3_ENDPOINT` is set.
- Nessie 0.109.0 gives `s3.path-style-access` to clients: no Nessie fallback template.

## Resume here

1. No work is in progress. Ask the user (in Italian) for the next goal. Candidates:
   Phase 5 (scenarios) and Phase 6 (evaluation), deferred in `NOTES.md` D14; the open
   points below.
2. For new work: brainstorm with `superpowers:brainstorming`, write the plan with
   `superpowers:writing-plans`, open one GitHub issue per task, then execute.

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
- `data/rustfs/` and `secrets/rustfs/` exist (git-ignored).
- Docker volumes: `pgdata-rustfs`, `rest-fixture-data-rustfs` (variant) and `pgdata` (one
  switch test to the AWS configuration; empty catalogs).

## State of the EC2 VM

- After the regression the VM is on the deleted branch `feat/rustfs-onprem`. At the next
  use there: `git checkout main && git pull`, then `git branch -D feat/rustfs-onprem`.

- The AWS stack runs there with `postgres` and `spark` only (`COMPOSE_PROFILES=`).
- `secrets/spark_user.env` exists there. Catalogs: only the empty namespace `smoke`. The S3
  bucket has no object under `polaris/`, `nessie/` or `rest/`.
- The VM role can only **list** under `polaris/`: drop every Polaris table with
  `DROP TABLE ... PURGE`; a left file must be deleted by the user from CloudShell.
- The VM `.env` needs the RustFS lines of `.env.example` only if the variant runs there.

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
Read docs/HANDOFF.md (on main). The RustFS variant is merged. Follow "Resume here":
ask me for the next goal.
```
