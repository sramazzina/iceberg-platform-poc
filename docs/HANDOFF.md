# Handoff — Iceberg catalog lab

- Date: 2026-10-29
- From: Claude Code session on the EC2 lab VM (Phases 1, 3 and 2)
- To: the next Claude Code session on the EC2 lab VM

## Where we are

| Item | State |
|---|---|
| Requirements | `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` (Italian; corrected on 2026-10-29) |
| Design spec | `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md` — approved, updated on 2026-10-29 |
| Plan (Stage 1, Phase 1) | `docs/superpowers/plans/2026-10-28-stage1-and-phase1.md` — Tasks 1-9 |
| Plan (Phase 3) | `docs/superpowers/plans/2026-10-28-phase3-nessie.md` — Tasks 10-12 |
| Plan (Phase 2) | `docs/superpowers/plans/2026-10-29-phase2-polaris.md` — Tasks 13-17 |
| GitHub milestone | "S1 — Iceberg catalog lab" |
| GitHub issues | #1-#9, #13-#15 and #17-#21, one per plan task (all done); #22 (Nessie CLI, later phase, open) |
| Stage 1 (AWS scripts) | Merged (PR #10) |
| Phase 1 (Postgres, Spark image, S3 acceptance test) | Merged (PR #11) |
| Phase 3 (Nessie) | Merged (PR #16) |
| Phase 2 (Polaris) and optional catalogs | Merged (PR #23) |
| Next step | Write the Phase 4 plan (baseline `rest-fixture`) |

## Resume here

1. PR #23 is merged and its branch is deleted. Work starts from `main`.
2. Phase 4 (baseline): brainstorm briefly, then write the plan with `superpowers:writing-plans`,
   create one issue per task, and execute with subagent-driven development. Read the code, not
   the old plans: every plan has an "Execution notes (after review)" section, because the reviews
   changed the code.

## State of the VM

- The stack runs with `postgres` and `spark` only. `.env` has `COMPOSE_PROFILES=` (no catalog),
  as the user wants by default.
- `secrets/spark_user.env` exists (Polaris `spark_user` credentials, git-ignored, mode 600).
- The Polaris database holds `lab_catalog`, `spark_user` and the roles. The Polaris and Nessie
  catalogs hold no table except the empty namespace `smoke`.
- The S3 bucket has no object under `polaris/`, `nessie/` or `rest/`.
- To use a catalog: set `COMPOSE_PROFILES=polaris` (or `nessie`) in `.env`, run `make up`, then
  `make sql-polaris` (or `make sql-nessie`).

## Decisions already taken with the user (do not ask again)

1. All implementation runs on this EC2 VM.
2. Repository root = this repository (not `iceberg-catalog-lab/`). The repository is **public**: no
   account ID, ARN, bucket name, external ID, password or secret in any tracked file.
3. The VM already exists and already has an IAM role. `aws/setup.sh` discovers the role from
   `INSTANCE_ID` and adds the inline policy `iceberg-lab-vm`; it does not create the VM, the role
   or the instance profile.
4. `aws/setup.sh` and `aws/teardown.sh` are run **by the user in AWS CloudShell**, never on the VM.
   Claude never creates or changes AWS resources (requirement 6). If an AWS permission is missing,
   stop and give the user the command or policy to apply. CloudShell is outside the VPC: the user
   cannot reach the VM private IP from it, and does not need to.
5. The user reaches the VM with SSH. Remote access to the lab ports is only through an SSH or SSM
   tunnel (`README.md`, "Access from your machine"); the ports stay on `127.0.0.1`.
6. Spark image: official `apache/spark:4.1.3-scala2.13-java17-python3-ubuntu`, with the system
   Python 3.10 (pandas 2.3.3, pyarrow 25.0.1 pinned for Python 3.10).
7. Iceberg client 1.11.0 (the version Polaris 1.8.0 and Nessie 0.109.0 are built against), not 1.12.0.
8. Versions were verified online on 2026-10-28; the list with sources is in `VERSIONS.md`.
9. One plan and one PR per phase. Inside a PR, one commit per task plus review-fix commits.
10. Phase 3 (Nessie) ran before Phase 2 (Polaris) (`NOTES.md` D9).
11. The catalogs are off by default; `COMPOSE_PROFILES` in `.env` selects them. The catalogs do
    not have to run together; the scenarios run on one catalog at a time (`NOTES.md` D11).
12. The Nessie CLI is a requirement for a later phase (issue #22, spec section 5.0.1).
13. `spark.driver.memory` stays 4g for now; lower it to 2g if memory is short (VM: 2 vCPU, 7 GiB).

## How to execute (from `CLAUDE.md` and `~/.claude/CLAUDE.md`)

- Brainstorm with `superpowers:brainstorming`, write plans with `superpowers:writing-plans`, and
  commit specs and plans on the phase branch.
- Execute the plan with `superpowers:subagent-driven-development`: one fresh implementer subagent
  per task, then spec-compliance review, then code-quality review. Do not ask for an execution mode.
- Implementer and fact-finding subagents: `model: "sonnet"`. Reviews, synthesis and documentation
  stay with the main model.
- Claude creates one GitHub issue per plan task before the execution, and ticks its checklist
  (`- [x]`) after the task.
- Commit messages, PR bodies and issues: English, Conventional Commits, **no `Co-Authored-By`
  line and no Claude attribution** ("Generated with Claude Code").
- Do not push after every commit. Push the batch when the PR is ready; open the PR last.
  The PR body has `Closes #N` for every grouped issue. The user merges; never merge yourself.
- After the user confirms the merge: delete the branch locally and on the remote, then
  `git checkout main && git pull`.
- Chat with the user in Italian, with an explanatory tone; every file, commit, issue and PR in
  English. Documentation follows ASD-STE100.

## Rules for work on the VM

- `.env` holds real values: never print it, never commit it. Only the line
  `COMPOSE_PROFILES=...` may be changed with `sed` (restore the user's value at the end).
- Never print `secrets/spark_user.env`.
- The VM role can only **list** under `polaris/`; it cannot read, write or delete there. Every
  Polaris table must be dropped with `DROP TABLE ... PURGE`. A file left under `polaris/` must be
  deleted by the user from CloudShell.
- Do not run `make reset` or `docker compose down -v` without the user's approval (they delete the
  Postgres volume).
- In this shell `cat` is an alias for a missing `bat`: use `command cat` or the Write tool.

## Open points to watch

- Phase 4: the profile `baseline` renders the Spark catalog `rest` from
  `spark/conf/catalogs/baseline.conf`. `tests/smoke-test.sh` assumes that the profile, the service
  and the Spark catalog have the same name; for `baseline` they differ (service `rest-fixture`,
  catalog `rest`), so it needs a map.
- `apache/iceberg-rest-fixture` has no tag for Iceberg 1.11; the lab pins 1.10.1.
- Nessie publishes its management port on `127.0.0.1:9000`. A local MinIO (on-premise) also
  uses port 9000: map one of them to another host port.
- Deferred: AWS CLI endpoint for on-premise S3 (`S3_ENDPOINT`), Polaris on-premise
  (`stsEndpoint`/`stsUnavailable`), pinning of transitive pip dependencies, GPG check of the AWS
  CLI archive.
- The name of the existing VM role no longer describes what it does after `setup.sh` added the
  lab policy. The user knows.

## Kick-off prompt for the next session

```text
Read docs/HANDOFF.md, CLAUDE.md, NOTES.md, README.md and the spec. Then follow
"Resume here": start the Phase 4 (baseline) brainstorming.
```
