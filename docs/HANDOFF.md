# Handoff — Iceberg catalog lab

- Date: 2026-10-28
- From: Claude Code session on the developer workstation (WSL)
- To: Claude Code session on the EC2 lab VM

## Where we are

| Item | State |
|---|---|
| Requirements | `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` (Italian) |
| Design spec | `docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md` — approved |
| Plan | `docs/superpowers/plans/2026-10-28-stage1-and-phase1.md` — Stage 1 (Tasks 1-6) and Phase 1 (Tasks 7-9) |
| Plan (Phase 3) | `docs/superpowers/plans/2026-10-28-phase3-nessie.md` — Tasks 10-12 |
| Plan (Phase 2) | `docs/superpowers/plans/2026-10-29-phase2-polaris.md` — Tasks 13-17 |
| GitHub milestone | "S1 — Iceberg catalog lab" |
| GitHub issues | #1-#9, #13-#15 and #17-#21, one per plan task; #22 (Nessie CLI, later phase) |
| Stage 1 (AWS scripts) | Merged (PR #10) |
| Phase 1 (Postgres, Spark image, S3 acceptance test) | Merged (PR #11) |
| Phase 3 (Nessie) | Merged (PR #16) |
| Phase 2 (Polaris) and optional catalogs | Done on branch `phase2-polaris`. PR pending |
| Next step | Write the Phase 4 plan (baseline `rest-fixture`) |

## Decisions already taken with the user (do not ask again)

1. All implementation runs on this EC2 VM. The workstation was used only for spec, plan and issues.
2. Repository root = this repository (not `iceberg-catalog-lab/`). The repository is **public**: no
   account ID, ARN, bucket name, external ID, password or secret in any tracked file.
3. The VM already exists and already has an IAM role. `aws/setup.sh` discovers the role from
   `INSTANCE_ID` and adds the inline policy `iceberg-lab-vm`; it does not create the VM, the role
   or the instance profile.
4. `aws/setup.sh` and `aws/teardown.sh` are run **by the user in AWS CloudShell**, never on the VM.
   Claude never creates or changes AWS resources (requirement 6). If an AWS permission is missing,
   stop and give the user the command or policy to apply.
5. The user reaches the VM with SSH. Docker, the Compose plugin, the AWS CLI and Claude Code are
   installed on the VM.
6. Spark image: official `apache/spark:4.1.3-scala2.13-java17-python3-ubuntu`, with the system
   Python 3.10 (pandas 2.3.3, pyarrow 25.0.1 pinned for Python 3.10).
7. Iceberg client 1.11.0 (the version Polaris 1.8.0 and Nessie 0.109.0 are built against), not 1.12.0.
8. Versions were verified online on 2026-10-28; the full list with sources is in the plan, Task 6.
9. PR grouping: PR A = issues #1-#6 (Stage 1, branch `stage1-aws-scripts`);
   PR B = issues #7-#9 (Phase 1). Phases 2-6 get one plan and one PR each, planned on the VM
   after Phase 1 passes.
10. Phase 3 (Nessie) runs before Phase 2 (Polaris) (2026-10-28, `NOTES.md` D9).
11. The catalogs are off by default; `COMPOSE_PROFILES` in `.env` selects them. The catalogs do
    not have to run together (2026-10-29, `NOTES.md` D11).
12. The Nessie CLI is a requirement for a later phase (2026-10-29, issue #22).

## How to execute (from `CLAUDE.md`)

- Execute the plan with `superpowers:subagent-driven-development`: one fresh implementer subagent
  per task, then spec-compliance review, then code-quality review. Do not ask for an execution mode.
- Implementer subagents: `model: "sonnet"`. Give them the conventions section and the task section
  of the plan.
- After each task: tick the checklist items of the matching GitHub issue (`- [x]`).
- Commit messages: English, Conventional Commits, **no `Co-Authored-By` line**.
- Do not push after every commit. Push the batch when the PR is ready; open the PR last.
  The PR body has `Closes #N` for every grouped issue. The user merges; never merge yourself.
- After the user confirms the merge: delete the branch locally and on the remote, then
  `git checkout main && git pull`.
- Chat with the user in Italian; every file, commit, issue and PR in English.

## Gate between Stage 1 and Phase 1

Phase 1 needs real AWS resources. After PR A is merged, the user:

1. runs `aws/setup.sh` in CloudShell (`aws/README-aws.md`);
2. creates `.env` on the VM from `.env.example` with the `setup.sh` output;
3. runs the "Check from the VM" commands of `aws/README-aws.md`.

Only then start Task 7.

## Open points to watch

- The existing VM role may have permissions beyond the lab policy. The user was asked to check it.
- Polaris with `relational-jdbc` needs the admin-tool bootstrap job and the `polaris_schema` schema
  (already in the Postgres init script of Task 7). Details for Phase 2 are in the spec, section 5.
- `apache/iceberg-rest-fixture` has no tag for Iceberg 1.11; the lab pins 1.10.1.
- `spark` waits for a healthy `nessie`, so `make up` always starts Nessie.
- Nessie publishes its management port on `127.0.0.1:9000`. A local MinIO (on-premise) also
  uses port 9000: map one of them to another host port.
- Phase 4: the profile `baseline` renders the Spark catalog `rest` from
  `spark/conf/catalogs/baseline.conf`, and `tests/smoke-test.sh` needs a map from the profile
  to the service (`rest-fixture`) and the catalog (`rest`).

## Kick-off prompt for the VM session

```text
Read docs/HANDOFF.md, CLAUDE.md, the spec and the plan it points to.
Then execute the plan from Task 1 with subagent-driven development,
on a new branch stage1-aws-scripts. Stop at the gate before Task 7.
```
