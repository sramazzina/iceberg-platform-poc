# Handoff — Iceberg catalog lab

- Date: 2026-10-29 (evening)
- From: Claude Code session on the user's workstation (Windows, WSL2, Docker Desktop):
  market analysis, design, plan and Task 23 of the on-premise variant with RustFS
- To: the next Claude Code session on the **same workstation**

## Where we are

| Item | State |
|---|---|
| Requirements | `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` (Italian) |
| Lab design spec | `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md` |
| Stage 1, Phases 1-4, Nessie CLI | Merged (PRs #10, #11, #16, #23, #27, #30, #32) |
| Phase 5 (scenarios), Phase 6 (evaluation) | Deferred (`NOTES.md` D14) |
| **On-premise variant with RustFS** | **In progress** on the local branch `feat/rustfs-onprem` (not pushed) |
| RustFS spec | `docs/superpowers/specs/2026-10-29-rustfs-onprem-design.md` (on the branch; approved) |
| RustFS plan | `docs/superpowers/plans/2026-10-29-rustfs-onprem.md` (on the branch) — Tasks 23-28 |
| GitHub issues | #33 (T23, done, checklist ticked), #34 (T24), #35 (T25), #36 (T26), #37 (T27), #38 (T28) — open |
| One PR for #33-#38 | Not opened yet (open it last) |

Commits on `feat/rustfs-onprem` (local only):

| Commit | Content |
|---|---|
| `f7f1f5d` | Spec |
| `02c8a4d` | Plan, spec update (own state of the variant) |
| `321deeb` | Task 23: `docker-compose.rustfs.yml` (service `rustfs`, own volumes), `tests/compose-variant.sh`, Makefile, `.env.example`, `.gitignore` |
| `dcfea72` | Task 23 review fixes |
| `36c603d` | Plan: section "Execution environment" (WSL2 workstation) |

Task 23 passed the spec review and the code-quality review (approve with minor; the minor
fixes are in `dcfea72`).

## Resume here

1. `git checkout feat/rustfs-onprem`. Work from this branch.
2. Read the plan section **"Execution environment (changed on 2026-10-29, after Task 23)"**
   first. It overrides the "Conventions" section: the plan was written for the EC2 VM, but
   execution runs on this workstation.
3. Continue with **Task 24** (`rustfs-setup`, issue #34), then Tasks 25-28, with
   `superpowers:subagent-driven-development`: one implementer subagent (`model: "sonnet"`) per
   task, then a spec review and a code-quality review (main model). Tick the issue checklist
   after each task.
4. The subagents read the task text from the plan by line range: the header and the
   "Execution environment", "Facts", "Conventions" and "File map" sections, plus the lines
   of their task (`grep -n '^## ' <plan>` gives the ranges).
5. After Task 28: final review of the whole branch, push the batch, open one PR with
   `Closes #33` … `Closes #38`. The PR body must say that the AWS regression (Task 27 Step 3)
   is not run yet: the user runs it on the EC2 VM before the merge.

## State of this workstation

- Windows, WSL2 (kernel `6.18.33.2-microsoft-standard-WSL2`), Docker Desktop 29.9.2,
  20 CPUs, 32 GB. No AWS credentials, no AWS stack.
- `.env` is a **local** file for the RustFS variant (made from `.env.example` on
  2026-10-29): `COMPOSE_FILE=docker-compose.yml:docker-compose.rustfs.yml`,
  `S3_BUCKET=iceberg-lab`, `COMPOSE_PROFILES=` (no catalog), random local passwords and
  keys, no AWS value. Claude may change its lines; never print it.
- The variant runs: `postgres`, `rustfs`, `spark` (all healthy). `rustfs-setup` does not
  exist yet (Task 24), so the bucket and the users do not exist yet.
- `data/rustfs/` (RustFS data, owned by uid 1000) and `secrets/rustfs/` exist. Both are
  git-ignored on the branch (`/data/`, `secrets/`). On `main`, `data/` shows as untracked.
- Docker volumes: `pgdata-rustfs` (variant) and `pgdata` (made by one switch test to the AWS
  configuration; empty catalogs).
- The scratch file `rustfs-lab.env` of the previous session is gone; the local `.env`
  replaces it.

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

- Task 25: Nessie may not give `s3.path-style-access` to clients. The plan has the fallback
  (`spark/conf/s3-endpoint/nessie.conf`).
- Task 26: RustFS rejects a session policy over 2048 bytes; Polaris may need `stsEndpoint`.
  The plan lists the checks in order.
- RustFS issue rustfs/rustfs#2766 (`DeleteObjects` and the bucket ARN): report before you
  change a policy.
- The RustFS log warns that it cannot write `/logs` when it runs as `LAB_UID`; it logs to
  stdout. Harmless.
- From the AWS work: Nessie management port `127.0.0.1:9000` (RustFS uses host ports
  9100/9101 for this reason); deferred pinning of transitive pip dependencies and the GPG
  check of the AWS CLI archive.

## Kick-off prompt for the next session

```text
Read docs/HANDOFF.md (on main), then git checkout feat/rustfs-onprem and read the plan
docs/superpowers/plans/2026-10-29-rustfs-onprem.md, section "Execution environment" first.
Continue with Task 24 as described in "Resume here".
```
