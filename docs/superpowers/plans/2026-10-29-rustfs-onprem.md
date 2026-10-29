# Iceberg catalog lab — On-premise variant with RustFS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Compose override `docker-compose.rustfs.yml` that runs the whole lab on RustFS (S3 API and STS on a local directory) instead of AWS S3, with Polaris credential vending through the RustFS STS.

**Architecture:** `.env` selects the variant with `COMPOSE_FILE=docker-compose.yml:docker-compose.rustfs.yml`. The override adds the services `rustfs` and `rustfs-setup` (bucket, users `polaris` and `lab`, policies), gives the existing services the RustFS endpoint and the keys of their user, and gives the variant its own state (Postgres volume, `rest` catalog volume, `secrets/rustfs/`). The AWS stack does not change.

**Tech Stack:** RustFS 1.0.4 (`rustfs/rustfs`, Apache-2.0), RustFS CLI `rc` 0.1.36 (`rustfs/rc`, Apache-2.0), Docker Compose override files, POSIX sh, Bash, jq.

**Spec:** `docs/superpowers/specs/2026-10-29-rustfs-onprem-design.md`.

---

## Facts verified on 2026-10-29

Source: research report in the brainstorming session (RustFS tag 1.0.4, Polaris tag
`apache-polaris-1.8.0`, Nessie tag `nessie-0.109.0`, Iceberg tag `apache-iceberg-1.10.1`).

- Image `rustfs/rustfs:1.0.4` (Docker Hub, Alpine). S3 API and STS on 9000, console on 9001.
  Environment: `RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY` (root), `RUSTFS_VOLUMES` (default
  `/data`), `RUSTFS_ADDRESS` (`:9000`), `RUSTFS_CONSOLE_ENABLE`, `RUSTFS_CONSOLE_ADDRESS`
  (`:9001`), `RUSTFS_REGION` (default `us-east-1`). User `rustfs`, uid 10001. No image
  healthcheck; `curl` is in the image; health endpoint `http://127.0.0.1:9000/health`.
- `AssumeRole` is `POST /` on port 9000. RustFS ignores `RoleArn`. The temporary credentials
  inherit the policies of the calling user, restricted by the session policy (at most 2048
  bytes). The caller must be a built-in user (`rc admin user add`), not a service account.
- `rustfs/rc:v0.1.36`: entrypoint `rc`, Alpine, user `rc`. Documented commands:
  `rc alias set <alias> <url> <key> <secret>`, `rc mb <alias>/<bucket>`,
  `rc admin user add <alias>/ <user> <secret>`, `rc admin policy create <alias>/ <name> <file>`
  (some docs show `--file <file>`), `rc admin policy attach <alias>/ <name> --user <user>`.
- Polaris 1.8.0 `AwsStorageConfigInfo`: `endpoint` (clients see it), `endpointInternal`,
  `stsEndpoint` (default `endpointInternal`, then `endpoint`), `stsUnavailable`,
  `pathStyleAccess`, `roleArn`. `polaris/setup/setup.sh` already sends `endpoint` and
  `pathStyleAccess` when `S3_ENDPOINT` is set.
- Nessie: `NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_ENDPOINT` and `..._PATH_STYLE_ACCESS`
  are already in `docker-compose.yml`. Nessie gives `s3.endpoint` to clients (`external-endpoint`,
  else `endpoint`). Not verified: whether it also gives `s3.path-style-access`.
- `apache/iceberg-rest-fixture:1.10.1`: `CATALOG_S3_ENDPOINT` → `s3.endpoint`,
  `CATALOG_S3_PATH__STYLE__ACCESS` → `s3.path-style-access`. It does not give them to clients.
- RustFS issues to remember: rustfs/rustfs#2699 (`s3:ListBucket` with `s3:prefix` conditions,
  closed), #2766 (`DeleteObjects` needed a bucket ARN permission, closed), #4832 (AssumeRole
  caller rules).

## Conventions for every task

- All file content, comments, commit messages: English. ASD-STE100 style in documentation.
- Commit messages: Conventional Commits, **no `Co-Authored-By` line** and no Claude attribution.
- Do not push. The controller pushes the batch and opens the PR.
- Never write a real account ID, bucket name, ARN, external ID, password or secret into a
  tracked file. The fake account `123456789012` is allowed (`tests/check-no-secrets.sh`).
- **Do not change `.env`.** It holds the user's AWS values. To run the RustFS variant, load
  the controller's file `RF_ENV` into the shell. Shell variables override `.env` in Compose,
  and `.env` has no `COMPOSE_FILE` and no `RUSTFS_*` line. Every command that must run on the
  variant has this form (the shell state does not persist between tool calls):

  ```bash
  bash -c 'set -a; . "$RF_ENV"; set +a; <command>'
  ```

  `RF_ENV=/tmp/claude-1000/-home-sramazzina-work-dev-sramazzina-iceberg-platform-poc-docs/72f79856-2251-4d06-9b30-cb990b84db23/scratchpad/rustfs-lab.env`.
  Never print this file. Commands without the prefix run on the AWS stack.
  `RF_ENV` holds only `COMPOSE_FILE`, the two image pins and the six `RUSTFS_*_KEY` values.
  It does not hold `S3_BUCKET` or `AWS_REGION`: `tests/catalog-smoke.sh` sources `.env`,
  so the variant uses the bucket name and the region of `.env` (a local bucket in RustFS).
- Never print `.env`, `secrets/spark_user.env` or `secrets/rustfs/spark_user.env`.
- Never run `aws/setup.sh` or `aws/teardown.sh`, and never change an AWS resource.
- No `${VAR:?}` in a Compose file: `make lint` renders the files against `.env.example`.
- In this shell `cat` is an alias for a missing `bat`: use `command cat` or the Write tool.
- Do not run `make reset` or `docker compose down -v`.
- At the end of each task, run `make up` without the `RF_ENV` prefix and with no
  `COMPOSE_PROFILES` in the shell: the stack returns to the AWS stack and the `.env` selection.
- Branch: `feat/rustfs-onprem` (already checked out).

## File map

| File | Responsibility | Task |
|---|---|---|
| `docker-compose.rustfs.yml` (new) | The variant: `rustfs`, `rustfs-setup`, overrides, own state | 23-26 |
| `tests/compose-variant.sh` (new) | Static checks of both Compose configurations | 23-26 |
| `Makefile` | `lint` runs `compose-variant.sh`; `up` creates the state directories, removes orphans | 23 |
| `.env.example` | Section "RustFS (on-premise)", image pins | 23 |
| `.gitignore` | `data/` | 23 |
| `rustfs/setup/setup.sh` (new) | Idempotent bucket, users and policies | 24 |
| `rustfs/setup/policy-polaris.json`, `rustfs/setup/policy-lab.json` (new) | Policies with `${S3_BUCKET}` | 24 |
| `tests/rustfs-setup.sh` (new) | Second run of `rustfs-setup` exits 0 | 24 |
| `tests/smoke-test.sh` | Runs `rustfs-setup.sh` on the variant | 24 |
| `spark/conf/s3-endpoint/baseline.conf` (new) | Endpoint and path-style for the catalog `rest` | 25 |
| `spark/entrypoint.sh` | Appends `s3-endpoint/<catalog>.conf` when `S3_ENDPOINT` is set | 25 |
| `tests/spark-config.sh` | Assertions for the endpoint template | 25 |
| `tests/catalog-selection.sh` | Skips on the variant | 27 |
| `README.md`, `NOTES.md`, `VERSIONS.md` | Documentation | 28 |

---

## Task 23: RustFS service, own state, `.env.example`, Makefile

**Files:**
- Create: `docker-compose.rustfs.yml`, `tests/compose-variant.sh`
- Modify: `Makefile`, `.env.example`, `.gitignore`

- [ ] **Step 1: Check that RustFS runs with the host UID (spec section 6.3)**

```bash
dir=/tmp/claude-1000/-home-sramazzina-work-dev-sramazzina-iceberg-platform-poc-docs/72f79856-2251-4d06-9b30-cb990b84db23/scratchpad/rustfs-uid-test
mkdir -p "$dir"
docker run -d --name rustfs-uid-test --user "$(id -u)" \
  -e RUSTFS_ACCESS_KEY=uidtestadmin -e RUSTFS_SECRET_KEY=uidtestsecret \
  -v "$dir:/data" rustfs/rustfs:1.0.4
docker exec rustfs-uid-test curl -fsS --retry 15 --retry-all-errors --retry-delay 2 http://127.0.0.1:9000/health
docker logs rustfs-uid-test 2>&1 | tail -n 30
ls -lan "$dir"
docker rm -f rustfs-uid-test
```

Expected: the health call succeeds, the log has no permission error, and the files in `$dir`
belong to the host UID. If RustFS fails because of a path it cannot write (for example
`/logs`), try to move that path with an environment variable that the log or
`docker run --rm --entrypoint sh rustfs/rustfs:1.0.4 -c 'cat /entrypoint.sh'` names, and
repeat. If no setting works, do not use `user:` in Step 4. Report the fallback to the
controller (the README then documents `sudo chown 10001:10001 <data dir>`), and status
DONE_WITH_CONCERNS.

- [ ] **Step 2: Write the failing static test**

Create `tests/compose-variant.sh` (mode 755):

```bash
#!/usr/bin/env bash
# Static checks of the Compose configuration of the AWS stack and of the RustFS variant
# (spec 2026-10-29-rustfs-onprem, sections 6 and 8). No container runs.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

# Always the template: the result must not depend on the values of the user's .env.
# Shell variables still override it (Compose rule).
env_file=.env.example

# config FILES: the rendered configuration (JSON) for COMPOSE_FILE=FILES, every profile on.
config() {
  COMPOSE_FILE="$1" COMPOSE_PROFILES='*' docker compose --env-file "$env_file" \
    config --format json 2>/dev/null || echo '{}'
}
# q JSON FILTER: the jq result as raw text.
q() { jq -r "$2" <<<"$1" 2>/dev/null || echo "jq failed"; }

# src JSON SERVICE TARGET: the source of the mount of SERVICE on the container path TARGET.
src() {
  jq -r --arg s "$2" --arg t "$3" \
    '.services[$s].volumes[]? | select(.target == $t) | .source' <<<"$1" 2>/dev/null || echo "jq failed"
}

aws=$(config docker-compose.yml)
rustfs=$(config docker-compose.yml:docker-compose.rustfs.yml)

echo "compose variant: AWS stack"
assert_eq "$(q "$aws" '.services | has("rustfs")')" "false" "no rustfs service"
assert_eq "$(src "$aws" postgres /var/lib/postgresql)" "pgdata" "postgres data on the volume pgdata"
assert_eq "$(src "$aws" rest-fixture /home/iceberg)" "rest-fixture-data" "rest catalog on the volume rest-fixture-data"

echo "compose variant: RustFS"
assert_eq "$(q "$rustfs" '.services.rustfs.image')" "$(sed -n 's/^RUSTFS_IMAGE=//p' .env.example)" "rustfs image pinned in .env.example"
assert_eq "$(q "$rustfs" '.services.rustfs.environment.RUSTFS_VOLUMES')" "/data" "rustfs data in /data"
assert_eq "$(q "$rustfs" '.services.rustfs.volumes[] | select(.target == "/data") | .type')" "bind" "rustfs data on a bind mount"
assert_eq "$(q "$rustfs" '[.services.rustfs.ports[] | "\(.host_ip):\(.published)->\(.target)"] | join(",")')" \
  "127.0.0.1:9100->9000,127.0.0.1:9101->9001" "rustfs ports on 127.0.0.1:9100 and 9101"
assert_eq "$(src "$rustfs" postgres /var/lib/postgresql)" "pgdata-rustfs" "postgres data on the volume pgdata-rustfs"
assert_eq "$(src "$rustfs" rest-fixture /home/iceberg)" "rest-fixture-data-rustfs" "rest catalog on the volume rest-fixture-data-rustfs"
assert_eq "$(src "$rustfs" postgres /docker-entrypoint-initdb.d | sed 's#.*/##')" "init" "postgres init scripts kept"

finish
```

If Step 1 kept `user:`, add before `finish`:

```bash
lab_uid=${LAB_UID:-$(sed -n 's/^LAB_UID=//p' "$env_file")}; lab_uid=${lab_uid:-1000}
assert_eq "$(q "$rustfs" '.services.rustfs.user')" "$lab_uid" "rustfs runs with LAB_UID"
```

- [ ] **Step 3: Run the test; it fails**

Run: `tests/compose-variant.sh`
Expected: the AWS assertions pass, the RustFS assertions FAIL (`docker-compose.rustfs.yml`
does not exist, `config` gives `{}`), exit 1.

Note: `docker compose config --format json` may print a named volume source with the project
prefix (`iceberg-lab_pgdata`). If it does, change the expected values to the printed form for
both stacks, and say so in the report.

- [ ] **Step 4: Write `docker-compose.rustfs.yml`**

```yaml
# On-premise variant: RustFS replaces AWS S3 (docs/superpowers/specs/2026-10-29-rustfs-onprem-design.md).
# Select it in .env: COMPOSE_FILE=docker-compose.yml:docker-compose.rustfs.yml
# Compose merges this file into docker-compose.yml: mappings merge by key, volumes by
# container path.

services:
  rustfs:
    image: ${RUSTFS_IMAGE}
    # The host user owns the files of the data directory (spec section 6.3).
    user: "${LAB_UID:-1000}"
    environment:
      RUSTFS_ACCESS_KEY: ${RUSTFS_ROOT_ACCESS_KEY}
      RUSTFS_SECRET_KEY: ${RUSTFS_ROOT_SECRET_KEY}
      RUSTFS_VOLUMES: /data
      RUSTFS_ADDRESS: ":9000"
      RUSTFS_CONSOLE_ENABLE: "true"
      RUSTFS_CONSOLE_ADDRESS: ":9001"
      # The same region as the S3 clients of the lab.
      RUSTFS_REGION: ${AWS_REGION}
    volumes:
      - ${RUSTFS_DATA_DIR:-./data/rustfs}:/data
    ports:
      # Host port 9000 is the Nessie management port: the S3 API is on 9100, the console on 9101.
      - "127.0.0.1:9100:9000"
      - "127.0.0.1:9101:9001"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:9000/health >/dev/null"]
      interval: 5s
      timeout: 5s
      retries: 30

  # Own state for the variant: the catalogs of the AWS stack point to AWS S3 (spec section 6.4).
  postgres:
    volumes:
      - pgdata-rustfs:/var/lib/postgresql

  rest-fixture:
    volumes:
      - rest-fixture-data-rustfs:/home/iceberg

volumes:
  pgdata-rustfs:
  rest-fixture-data-rustfs:
```

Without `user:` if Step 1 found no working setting.

- [ ] **Step 5: Add the RustFS section to `.env.example`**

Insert after the section "S3 storage" (before "Polaris credential vending"):

```bash
# ---- RustFS (on-premise) ------------------------------------------------------
# Uncomment to run the lab on RustFS instead of AWS S3. S3_BUCKET is then a local bucket
# name, AWS_REGION the RustFS region. S3_ENDPOINT, S3_PATH_STYLE_ACCESS, AWS_ACCESS_KEY_ID,
# AWS_SECRET_ACCESS_KEY and the Polaris role values are not used: the override sets them.
#COMPOSE_FILE=docker-compose.yml:docker-compose.rustfs.yml
# Host directory for the RustFS data. `make up` creates it. `make reset` does not delete it.
RUSTFS_DATA_DIR=./data/rustfs
# Keys (choose your own values; secrets: at least 8 characters).
# Root: used only by rustfs-setup and the web console.
RUSTFS_ROOT_ACCESS_KEY=rustfsadmin
RUSTFS_ROOT_SECRET_KEY=change-me
# User polaris: Polaris calls the RustFS STS with it to vend credentials.
RUSTFS_POLARIS_ACCESS_KEY=polaris
RUSTFS_POLARIS_SECRET_KEY=change-me
# User lab: Spark, Nessie and the rest catalog (nessie/ and rest/; only list on polaris/).
RUSTFS_LAB_ACCESS_KEY=lab
RUSTFS_LAB_SECRET_KEY=change-me
```

In the section "Pinned versions", after `REST_FIXTURE_IMAGE=...`, add:

```bash
RUSTFS_IMAGE=rustfs/rustfs:1.0.4
RUSTFS_RC_IMAGE=rustfs/rc:v0.1.36
```

- [ ] **Step 6: Update the Makefile**

Change the targets `lint` and `up`:

```make
lint:
	tests/lint.sh
	tests/check-no-secrets.sh
	tests/compose-variant.sh
```

```make
up:
	mkdir -p secrets secrets/rustfs
	@dir=$$(docker compose config --format json | jq -r '.services.rustfs.volumes[]? | select(.target == "/data") | .source') || exit 1; \
	if [ -n "$$dir" ]; then mkdir -p "$$dir"; fi
	@on=$$(docker compose config --services) || exit 1; \
	off=$$($(ALL_PROFILES) docker compose config --services | grep -vxF "$$on" || true); \
	if [ -n "$$off" ]; then $(ALL_PROFILES) docker compose stop $$off; fi
	docker compose up -d --build --wait --remove-orphans
```

`--remove-orphans` removes `rustfs` and `rustfs-setup` when the user switches back to the AWS
stack. The first two lines create `secrets/rustfs/` and the data directory as the host user,
before Docker can create them as root.

- [ ] **Step 7: Ignore the data directory**

Append to `.gitignore`:

```
data/
```

- [ ] **Step 8: Run the static tests; they pass**

Run: `tests/compose-variant.sh` — expected: all assertions pass.
Run: `make lint` — expected: `lint passed`, `no secrets found`, `all assertions passed`.

- [ ] **Step 9: Start the variant and check RustFS**

```bash
bash -c 'set -a; . "$RF_ENV"; set +a; COMPOSE_PROFILES= make up'
bash -c 'set -a; . "$RF_ENV"; set +a; docker compose ps --format "{{.Service}} {{.Health}}"'
ls -lan data/rustfs
```

Expected: `rustfs healthy`, `postgres healthy`, `spark healthy`; `data/rustfs` belongs to the
host UID (with `user:`). Then check `--remove-orphans` and the return to the AWS stack:

```bash
make up
docker compose ps -a --format "{{.Service}}"
```

Expected: no `rustfs` in the list; the AWS stack runs as before.

- [ ] **Step 10: Commit**

```bash
git add docker-compose.rustfs.yml tests/compose-variant.sh Makefile .env.example .gitignore
git commit -m "feat(rustfs): add the RustFS service and the own state of the on-premise variant"
```

---

## Task 24: `rustfs-setup` (bucket, users, policies)

**Files:**
- Create: `rustfs/setup/setup.sh`, `rustfs/setup/policy-polaris.json`, `rustfs/setup/policy-lab.json`, `tests/rustfs-setup.sh`
- Modify: `docker-compose.rustfs.yml`, `tests/compose-variant.sh`, `tests/smoke-test.sh`

- [ ] **Step 1: Check the `rc` command syntax**

```bash
for c in "--help" "alias set --help" "mb --help" "ls --help" "admin user add --help" \
  "admin user info --help" "admin policy create --help" "admin policy attach --help"; do
  echo "=== rc $c"; docker run --rm rustfs/rc:v0.1.36 $c 2>&1 | head -n 30
done
docker run --rm --entrypoint /bin/sh rustfs/rc:v0.1.36 -c 'id; echo "$HOME"; command -v sed'
```

Write down: the exact form of `policy create` (positional file or `--file`), whether the
alias can come from an environment variable (no keys on the command line), and the home
directory of the user `rc` (it must be writable: `rc` stores its aliases there). Use these
facts in Step 4. If `sh` or `sed` is missing, report BLOCKED.

- [ ] **Step 2: Write the failing tests**

Add to `tests/compose-variant.sh`, before `finish`:

```bash
assert_eq "$(q "$rustfs" '.services["rustfs-setup"].image')" "$(sed -n 's/^RUSTFS_RC_IMAGE=//p' .env.example)" "rustfs-setup image pinned in .env.example"
assert_eq "$(q "$rustfs" '.services["rustfs-setup"].depends_on.rustfs.condition')" "service_healthy" "rustfs-setup waits for a healthy rustfs"
assert_eq "$(src "$rustfs" rustfs-setup /setup | sed 's#.*/rustfs/#rustfs/#')" "rustfs/setup" "rustfs-setup mounts rustfs/setup"
```

Create `tests/rustfs-setup.sh` (mode 755):

```bash
#!/usr/bin/env bash
# RustFS setup test (spec 2026-10-29-rustfs-onprem, sections 7 and 8): rustfs-setup is
# idempotent. Run it on the RustFS variant, after `make up`.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tests/lib/assert.sh"
cd "$ROOT"

echo "rustfs setup"
status=0
out=$(docker compose run --rm -T rustfs-setup 2>&1) || status=$?
assert_eq "$status" "0" "a second run of rustfs-setup exits 0"
assert_contains "$out" "already present" "the bucket is already present"
assert_contains "$out" "user polaris with policy lab-polaris set" "user polaris set"
assert_contains "$out" "user lab with policy lab-lab set" "user lab set"
assert_contains "$out" "rustfs-setup: done" "rustfs-setup completes"
if ((status != 0)); then sed 's/^/    /' <<<"$out" | tail -n 20; fi

finish
```

- [ ] **Step 3: Run the tests; they fail**

Run: `tests/compose-variant.sh` — expected: the three new assertions FAIL.
Run: `bash -c 'set -a; . "$RF_ENV"; set +a; tests/rustfs-setup.sh'` — expected: FAIL
(no service `rustfs-setup`).

- [ ] **Step 4: Write the policies and the setup script**

`rustfs/setup/policy-polaris.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": ["arn:aws:s3:::${S3_BUCKET}"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"],
      "Resource": ["arn:aws:s3:::${S3_BUCKET}/polaris/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["sts:AssumeRole"],
      "Resource": ["*"]
    }
  ]
}
```

`rustfs/setup/policy-lab.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": ["arn:aws:s3:::${S3_BUCKET}"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"],
      "Resource": ["arn:aws:s3:::${S3_BUCKET}/nessie/*", "arn:aws:s3:::${S3_BUCKET}/rest/*"]
    }
  ]
}
```

`rustfs/setup/setup.sh`:

```sh
#!/bin/sh
# Idempotent RustFS setup (spec 2026-10-29-rustfs-onprem, section 7): the bucket S3_BUCKET,
# the users polaris and lab, and their policies. Runs in the rc image: POSIX sh, no bash.
set -eu

fail() { echo "rustfs-setup: $*" >&2; exit 1; }

for name in S3_BUCKET RUSTFS_ROOT_ACCESS_KEY RUSTFS_ROOT_SECRET_KEY RUSTFS_POLARIS_ACCESS_KEY \
  RUSTFS_POLARIS_SECRET_KEY RUSTFS_LAB_ACCESS_KEY RUSTFS_LAB_SECRET_KEY; do
  eval "value=\${$name:-}"
  [ -n "$value" ] || fail "$name is empty: set it in .env (see .env.example)"
done

rc alias set lab http://rustfs:9000 "$RUSTFS_ROOT_ACCESS_KEY" "$RUSTFS_ROOT_SECRET_KEY" >/dev/null \
  || fail "cannot connect to rustfs with the root keys"

if rc ls "lab/$S3_BUCKET" >/dev/null 2>&1; then
  echo "rustfs-setup: bucket $S3_BUCKET already present"
else
  rc mb "lab/$S3_BUCKET" >/dev/null || fail "cannot create the bucket $S3_BUCKET"
  echo "rustfs-setup: bucket $S3_BUCKET created"
fi

# user NAME ACCESS_KEY SECRET_KEY: sets the policy lab-NAME from /setup/policy-NAME.json and
# the user ACCESS_KEY with this policy. In RustFS the access key is the user name.
user() {
  policy=/tmp/policy-$1.json
  sed "s/\${S3_BUCKET}/$S3_BUCKET/g" "/setup/policy-$1.json" >"$policy"
  rc admin policy create lab/ "lab-$1" "$policy" >/dev/null || fail "policy lab-$1"
  rc admin user add lab/ "$2" "$3" >/dev/null || fail "user $1"
  rc admin policy attach lab/ "lab-$1" --user "$2" >/dev/null || fail "policy lab-$1 for the user $1"
  echo "rustfs-setup: user $1 with policy lab-$1 set"
}
user polaris "$RUSTFS_POLARIS_ACCESS_KEY" "$RUSTFS_POLARIS_SECRET_KEY"
user lab "$RUSTFS_LAB_ACCESS_KEY" "$RUSTFS_LAB_SECRET_KEY"

echo "rustfs-setup: done"
```

Adapt the `rc` calls to the facts of Step 1:
- `policy create`: use the form that `--help` shows.
- If `rc` reads an alias from an environment variable, use it instead of `rc alias set`, so the
  root keys are not on a command line.
- Idempotency rule: a second run must exit 0 and leave the same state. If a command fails
  when the object already exists (for example `policy attach` of a policy that is already
  attached), check first with the matching `info`/`list` command and skip the call. Do not
  hide errors with `|| true`.
- Never print a key or a secret.

- [ ] **Step 5: Add the service to `docker-compose.rustfs.yml`**

After the service `rustfs`:

```yaml
  rustfs-setup:
    image: ${RUSTFS_RC_IMAGE}
    depends_on:
      rustfs:
        condition: service_healthy
    # Creates the bucket, the users polaris and lab, and their policies. A second run
    # changes nothing (spec section 7).
    entrypoint: ["/bin/sh", "/setup/setup.sh"]
    environment:
      S3_BUCKET: ${S3_BUCKET}
      RUSTFS_ROOT_ACCESS_KEY: ${RUSTFS_ROOT_ACCESS_KEY}
      RUSTFS_ROOT_SECRET_KEY: ${RUSTFS_ROOT_SECRET_KEY}
      RUSTFS_POLARIS_ACCESS_KEY: ${RUSTFS_POLARIS_ACCESS_KEY}
      RUSTFS_POLARIS_SECRET_KEY: ${RUSTFS_POLARIS_SECRET_KEY}
      RUSTFS_LAB_ACCESS_KEY: ${RUSTFS_LAB_ACCESS_KEY}
      RUSTFS_LAB_SECRET_KEY: ${RUSTFS_LAB_SECRET_KEY}
    volumes:
      - ./rustfs/setup:/setup:ro
```

`make up --wait` fails when a one-shot service exits non-zero; with exit 0 it succeeds
(as for `polaris-setup`). Verify this in Step 7.

- [ ] **Step 6: Run the setup check from the smoke test**

In `tests/smoke-test.sh`, after `tests/postgres-init.sh`:

```bash
# The RustFS variant: rustfs-setup must be idempotent.
if docker compose config --services | grep -qx rustfs; then tests/rustfs-setup.sh; fi
```

- [ ] **Step 7: Run the tests; they pass**

```bash
tests/compose-variant.sh
make lint
bash -c 'set -a; . "$RF_ENV"; set +a; COMPOSE_PROFILES= make up'
bash -c 'set -a; . "$RF_ENV"; set +a; docker compose logs rustfs-setup'
bash -c 'set -a; . "$RF_ENV"; set +a; tests/rustfs-setup.sh'
```

Expected: all assertions pass. The first log shows `bucket ... created` (or `already
present`), the two `user ... set` lines and `rustfs-setup: done`. The log has no key.

- [ ] **Step 8: Return to the AWS stack and commit**

```bash
make up
git add rustfs/setup tests/rustfs-setup.sh tests/compose-variant.sh tests/smoke-test.sh docker-compose.rustfs.yml
git commit -m "feat(rustfs): create the bucket, the users polaris and lab, and their policies"
```

---

## Task 25: Spark, Nessie and the `rest` catalog on RustFS

**Files:**
- Create: `spark/conf/s3-endpoint/baseline.conf`
- Modify: `docker-compose.rustfs.yml`, `spark/entrypoint.sh`, `tests/spark-config.sh`, `tests/compose-variant.sh`

- [ ] **Step 1: Write the failing tests**

Add to `tests/compose-variant.sh`, before `finish`:

```bash
for s in spark nessie rest-fixture; do
  assert_eq "$(q "$rustfs" ".services[\"$s\"].depends_on[\"rustfs-setup\"].condition")" \
    "service_completed_successfully" "$s waits for rustfs-setup"
done
assert_eq "$(q "$rustfs" '.services.spark.environment | "\(.S3_ENDPOINT) \(.S3_PATH_STYLE_ACCESS) \(.AWS_ENDPOINT_URL)"')" \
  "http://rustfs:9000 true http://rustfs:9000" "spark uses the RustFS endpoint with path-style access"
assert_eq "$(q "$rustfs" '.services.nessie.environment | "\(.NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_ENDPOINT) \(.NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_PATH_STYLE_ACCESS)"')" \
  "http://rustfs:9000 true" "nessie uses the RustFS endpoint with path-style access"
assert_eq "$(q "$rustfs" '.services["rest-fixture"].environment | "\(.CATALOG_S3_ENDPOINT) \(.CATALOG_S3_PATH__STYLE__ACCESS)"')" \
  "http://rustfs:9000 true" "rest-fixture uses the RustFS endpoint with path-style access"
lab_key=$(sed -n 's/^RUSTFS_LAB_ACCESS_KEY=//p' "$env_file")
for s in spark nessie rest-fixture; do
  assert_eq "$(q "$rustfs" ".services[\"$s\"].environment.AWS_ACCESS_KEY_ID")" "$lab_key" "$s uses the keys of the user lab"
done
assert_eq "$(src "$rustfs" spark /run/lab-secrets | sed 's#.*/secrets/#secrets/#')" "secrets/rustfs" "spark reads secrets/rustfs"
assert_eq "$(q "$aws" '.services.spark.environment.AWS_ENDPOINT_URL')" "null" "AWS stack: no AWS_ENDPOINT_URL"
```

With the `RF_ENV` prefix, Compose uses the shell value of `RUSTFS_LAB_ACCESS_KEY`, not the
value in `.env.example`. So `lab_key` follows the same rule: the shell value when it is set,
else the value in `$env_file`. Use this line instead of the `lab_key=` line above:

```bash
lab_key=${RUSTFS_LAB_ACCESS_KEY:-$(sed -n 's/^RUSTFS_LAB_ACCESS_KEY=//p' "$env_file")}
```

The access key is not a secret (it is the user name); the secret key is never printed.

In `tests/spark-config.sh`:

1. The function `conf` must model the AWS stack on both stacks. Change it to:

```bash
# conf CATALOGS: the rendered spark-defaults.conf for LAB_CATALOGS=CATALOGS, on AWS (no endpoint).
conf() {
  docker compose run --rm --no-deps -T -e LAB_CATALOGS="$1" -e S3_ENDPOINT= spark \
    cat /opt/spark/conf/spark-defaults.conf 2>/dev/null || echo "command failed"
}

# conf_endpoint CATALOGS: the same, with an S3-compatible endpoint.
conf_endpoint() {
  docker compose run --rm --no-deps -T -e LAB_CATALOGS="$1" \
    -e S3_ENDPOINT=http://rustfs:9000 -e S3_PATH_STYLE_ACCESS=true spark \
    cat /opt/spark/conf/spark-defaults.conf 2>/dev/null || echo "command failed"
}
```

2. Before `finish`, add:

```bash
assert_not_contains "$rest" "spark.sql.catalog.rest.s3.endpoint" "no S3 endpoint for rest on AWS"
rest_endpoint=$(conf_endpoint baseline)
assert_contains "$rest_endpoint" "spark.sql.catalog.rest.s3.endpoint            http://rustfs:9000" "S3 endpoint for rest with S3_ENDPOINT"
assert_contains "$rest_endpoint" "spark.sql.catalog.rest.s3.path-style-access   true" "path-style access for rest with S3_ENDPOINT"
assert_not_contains "$(conf_endpoint nessie)" ".s3.endpoint" "no S3 endpoint template for nessie (Nessie gives it to clients)"
```

- [ ] **Step 2: Run the tests; they fail**

```bash
bash -c 'set -a; . "$RF_ENV"; set +a; tests/compose-variant.sh'
docker compose build spark && tests/spark-config.sh
```

Expected: the new assertions FAIL (no override, no template).

- [ ] **Step 3: Add the endpoint template and the entrypoint change**

`spark/conf/s3-endpoint/baseline.conf`:

```
# S3-compatible storage (S3_ENDPOINT is set): apache/iceberg-rest-fixture does not give the
# endpoint and the addressing style to clients, so Spark sets them for the catalog rest.
spark.sql.catalog.rest.s3.endpoint            ${S3_ENDPOINT}
spark.sql.catalog.rest.s3.path-style-access   ${S3_PATH_STYLE_ACCESS}
```

In `spark/entrypoint.sh`, replace:

```bash
    elif [[ -f $templates/catalogs/$catalog.conf ]]; then
      printf '\n'
      render_template "$templates/catalogs/$catalog.conf"
```

with:

```bash
    elif [[ -f $templates/catalogs/$catalog.conf ]]; then
      printf '\n'
      render_template "$templates/catalogs/$catalog.conf"
      # S3-compatible storage: the endpoint settings that the catalog does not give to clients.
      if [[ -n ${S3_ENDPOINT:-} && -f $templates/s3-endpoint/$catalog.conf ]]; then
        render_template "$templates/s3-endpoint/$catalog.conf"
      fi
```

- [ ] **Step 4: Add the overrides to `docker-compose.rustfs.yml`**

Insert after the service `rustfs-setup`:

```yaml
  # S3 clients of the user lab (spec section 7): nessie/ and rest/, only list on polaris/.
  nessie:
    depends_on:
      rustfs-setup:
        condition: service_completed_successfully
    environment:
      NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_ENDPOINT: http://rustfs:9000
      NESSIE_CATALOG_SERVICE_S3_DEFAULT_OPTIONS_PATH_STYLE_ACCESS: "true"
      AWS_ACCESS_KEY_ID: ${RUSTFS_LAB_ACCESS_KEY}
      AWS_SECRET_ACCESS_KEY: ${RUSTFS_LAB_SECRET_KEY}

  spark:
    depends_on:
      rustfs-setup:
        condition: service_completed_successfully
    environment:
      S3_ENDPOINT: http://rustfs:9000
      S3_PATH_STYLE_ACCESS: "true"
      # The AWS CLI in the container uses RustFS too.
      AWS_ENDPOINT_URL: http://rustfs:9000
      AWS_ACCESS_KEY_ID: ${RUSTFS_LAB_ACCESS_KEY}
      AWS_SECRET_ACCESS_KEY: ${RUSTFS_LAB_SECRET_KEY}
    volumes:
      - ./secrets/rustfs:/run/lab-secrets:ro
```

Merge the `rest-fixture` block of Task 23 with this content (one `rest-fixture` key only):

```yaml
  rest-fixture:
    depends_on:
      rustfs-setup:
        condition: service_completed_successfully
    environment:
      CATALOG_S3_ENDPOINT: http://rustfs:9000
      CATALOG_S3_PATH__STYLE__ACCESS: "true"
      AWS_ACCESS_KEY_ID: ${RUSTFS_LAB_ACCESS_KEY}
      AWS_SECRET_ACCESS_KEY: ${RUSTFS_LAB_SECRET_KEY}
    volumes:
      - rest-fixture-data-rustfs:/home/iceberg
```

- [ ] **Step 5: Run the static tests; they pass**

```bash
bash -c 'set -a; . "$RF_ENV"; set +a; tests/compose-variant.sh'
tests/compose-variant.sh
docker compose build spark && tests/spark-config.sh
make lint
```

Expected: all assertions pass, with and without the prefix.

- [ ] **Step 6: Run the acceptance tests on the variant**

```bash
bash -c 'set -a; . "$RF_ENV"; set +a; COMPOSE_PROFILES=nessie,baseline make up'
bash -c 'set -a; . "$RF_ENV"; set +a; COMPOSE_PROFILES=nessie,baseline tests/s3-access.sh'
bash -c 'set -a; . "$RF_ENV"; set +a; COMPOSE_PROFILES=nessie,baseline tests/nessie-service.sh'
bash -c 'set -a; . "$RF_ENV"; set +a; COMPOSE_PROFILES=nessie,baseline tests/catalog-smoke.sh nessie'
bash -c 'set -a; . "$RF_ENV"; set +a; COMPOSE_PROFILES=nessie,baseline tests/catalog-smoke.sh rest'
```

Expected: all `ok`. `s3-access.sh` shows the write under `rest/` and the denied write under
`polaris/` (the `lab` user).

If the Nessie catalog fails with an unknown host such as `<bucket>.rustfs`, Nessie does not
give `s3.path-style-access` to clients. Then add `spark/conf/s3-endpoint/nessie.conf` with
only:

```
# S3-compatible storage: Nessie gives the endpoint to clients, but not the addressing style.
spark.sql.catalog.nessie.s3.path-style-access   ${S3_PATH_STYLE_ACCESS}
```

change the last `spark-config.sh` assertion to check that the nessie block has
`spark.sql.catalog.nessie.s3.path-style-access   true` and no `.s3.endpoint`, and record the
finding for Task 28 (NOTES F1).

If a `DROP TABLE ... PURGE` or a cleanup fails with AccessDenied on `DeleteObjects`
(rustfs/rustfs#2766), report the exact error to the controller before you change a policy.

- [ ] **Step 7: Return to the AWS stack and commit**

```bash
make up
git add spark/conf/s3-endpoint spark/entrypoint.sh tests/spark-config.sh tests/compose-variant.sh docker-compose.rustfs.yml
git commit -m "feat(rustfs): run Spark, Nessie and the rest catalog on RustFS with the user lab"
```

---

## Task 26: Polaris credential vending through the RustFS STS

**Files:**
- Modify: `docker-compose.rustfs.yml`, `tests/compose-variant.sh`

- [ ] **Step 1: Write the failing test**

Add to `tests/compose-variant.sh`, before `finish`:

```bash
polaris_key=${RUSTFS_POLARIS_ACCESS_KEY:-$(sed -n 's/^RUSTFS_POLARIS_ACCESS_KEY=//p' "$env_file")}
assert_eq "$(q "$rustfs" '.services.polaris.environment.AWS_ACCESS_KEY_ID')" "$polaris_key" "polaris calls STS with the user polaris"
assert_eq "$(q "$rustfs" '.services.polaris.depends_on["rustfs-setup"].condition')" "service_completed_successfully" "polaris waits for rustfs-setup"
assert_eq "$(q "$rustfs" '.services["polaris-setup"].environment | "\(.S3_ENDPOINT) \(.S3_PATH_STYLE_ACCESS)"')" \
  "http://rustfs:9000 true" "polaris-setup gives the RustFS endpoint to the catalog"
assert_contains "$(q "$rustfs" '.services["polaris-setup"].environment.POLARIS_ROLE_ARN')" ":123456789012:" "placeholder role ARN with the fake account"
assert_eq "$(src "$rustfs" polaris-setup /secrets | sed 's#.*/secrets/#secrets/#')" "secrets/rustfs" "polaris-setup writes secrets/rustfs"
```

Run: `bash -c 'set -a; . "$RF_ENV"; set +a; tests/compose-variant.sh'` — expected: the five
new assertions FAIL.

- [ ] **Step 2: Add the Polaris overrides**

Append to the `services` of `docker-compose.rustfs.yml`:

```yaml
  # Polaris vends credentials through the RustFS STS (spec section 7): it calls AssumeRole
  # with the keys of the user polaris.
  polaris:
    depends_on:
      rustfs-setup:
        condition: service_completed_successfully
    environment:
      AWS_ACCESS_KEY_ID: ${RUSTFS_POLARIS_ACCESS_KEY}
      AWS_SECRET_ACCESS_KEY: ${RUSTFS_POLARIS_SECRET_KEY}

  polaris-setup:
    environment:
      # The catalog endpoint; stsEndpoint defaults to it.
      S3_ENDPOINT: http://rustfs:9000
      S3_PATH_STYLE_ACCESS: "true"
      # RustFS ignores RoleArn and ExternalId (spec section 3); setup.sh requires values.
      # 123456789012 is the fake test account.
      POLARIS_ROLE_ARN: arn:aws:iam::123456789012:role/rustfs-placeholder
      POLARIS_EXTERNAL_ID: rustfs-placeholder
    volumes:
      - ./secrets/rustfs:/secrets
```

- [ ] **Step 3: Run the static tests; they pass**

```bash
bash -c 'set -a; . "$RF_ENV"; set +a; tests/compose-variant.sh'
make lint
```

- [ ] **Step 4: Run the Polaris acceptance tests on the variant**

```bash
bash -c 'set -a; . "$RF_ENV"; set +a; COMPOSE_PROFILES=polaris make up'
bash -c 'set -a; . "$RF_ENV"; set +a; COMPOSE_PROFILES=polaris tests/polaris-service.sh'
bash -c 'set -a; . "$RF_ENV"; set +a; COMPOSE_PROFILES=polaris tests/catalog-smoke.sh polaris'
ls -la secrets/rustfs
```

Expected: all `ok`; `secrets/rustfs/spark_user.env` exists with mode 600 (do not print it);
`secrets/spark_user.env` of the AWS stack is unchanged (compare `stat -c %Y` before and after).

If the table write fails, read the Polaris log
(`bash -c 'set -a; . "$RF_ENV"; set +a; docker compose logs polaris' | grep -iE 'sts|assume|credential|denied' | tail -n 40`)
and the RustFS log. Known causes, in order:
1. The session policy is larger than 2048 bytes ("policy too large"): report it.
2. Polaris calls STS on the wrong endpoint: add `"stsEndpoint":"$S3_ENDPOINT"` to the `extra`
   of `polaris/setup/setup.sh` only if the log shows it, and add this file to the commit.
3. AccessDenied on `ListBucket` with an `s3:prefix` condition (rustfs/rustfs#2699): report it.
Do not set `stsUnavailable`: the spec requires vending.

- [ ] **Step 5: Return to the AWS stack and commit**

```bash
make up
git add docker-compose.rustfs.yml tests/compose-variant.sh
git commit -m "feat(rustfs): vend Polaris credentials through the RustFS STS"
```

---

## Task 27: Full verification on both stacks

**Files:**
- Modify: `tests/catalog-selection.sh`

- [ ] **Step 1: Skip `catalog-selection.sh` on the variant**

After the line `cd "$ROOT"` in `tests/catalog-selection.sh`, add:

```bash
# The service lists below are the lists of the AWS stack.
if docker compose config --services 2>/dev/null | grep -qx rustfs; then
  echo "catalog selection: skipped on the RustFS variant"
  exit 0
fi
```

This must come before the `trap`, so that the skip does not run `make up`.

- [ ] **Step 2: Run every test on the variant**

```bash
bash -c 'set -a; . "$RF_ENV"; set +a; tests/catalog-selection.sh'
for p in nessie polaris baseline nessie,polaris,baseline; do
  bash -c "set -a; . \"\$RF_ENV\"; set +a; COMPOSE_PROFILES=$p make up && COMPOSE_PROFILES=$p make smoke-test" \
    || echo "FAILED: $p"
done
bash -c 'set -a; . "$RF_ENV"; set +a; tests/spark-config.sh'
```

Expected: `skipped on the RustFS variant`; four green smoke runs (no `FAILED:` line).

- [ ] **Step 3: Run every test on the AWS stack (regression)**

```bash
tests/catalog-selection.sh
COMPOSE_PROFILES=nessie,polaris,baseline make up
COMPOSE_PROFILES=nessie,polaris,baseline make smoke-test
tests/spark-config.sh
make lint
```

Expected: all green. No object is left under `polaris/` on AWS (the smoke test checks it).

- [ ] **Step 4: Restore and commit**

```bash
make up
docker compose ps --format '{{.Service}}'
git add tests/catalog-selection.sh
git commit -m "test(rustfs): skip the catalog selection test on the RustFS variant"
```

Expected: `postgres` and `spark` only (the `.env` selection).

---

## Task 28: README, NOTES and VERSIONS

**Files:**
- Modify: `README.md`, `NOTES.md`, `VERSIONS.md`

- [ ] **Step 1: Replace the README section "On-premise S3 storage (not verified)"**

Replace the whole section (heading and text, up to `## Documents`) with:

```markdown
## On-premise with RustFS

The lab can run on a PC or on an on-premise server without AWS. RustFS replaces AWS S3: it
gives the S3 API and STS, and it keeps the data in a local directory. All catalogs work, and
Polaris vends credentials through the RustFS STS, as on AWS. Verified on Linux. Not verified
on macOS and Windows (WSL2) with Docker Desktop.

The variant has its own state: the Postgres volume `pgdata-rustfs`, the `rest` catalog
volume `rest-fixture-data-rustfs` and `secrets/rustfs/`. The state of the AWS stack stays
intact, so you can go back to it.

### Start

1. Copy the section "RustFS (on-premise)" and the lines `RUSTFS_IMAGE` and
   `RUSTFS_RC_IMAGE` from `.env.example` into `.env`, if they are missing.
2. In `.env`, uncomment `COMPOSE_FILE=docker-compose.yml:docker-compose.rustfs.yml`.
3. In `.env`, set `S3_BUCKET` (a local bucket name, for example `iceberg-lab`) and the six
   `RUSTFS_*_KEY` values. Each secret key has at least 8 characters.
4. Run `make up`. The service `rustfs-setup` creates the bucket, the user `polaris` (Polaris
   STS calls) and the user `lab` (Spark, Nessie, `rest`).
5. Run `make smoke-test`.

To go back to AWS, comment out `COMPOSE_FILE` and run `make up`.

### Web console

The RustFS console is on `127.0.0.1:9101`, the S3 API on `127.0.0.1:9100`. From your machine,
open a tunnel (see "Access from your machine") with `-L 9101:127.0.0.1:9101`, then open
`http://localhost:9101` and sign in with `RUSTFS_ROOT_ACCESS_KEY` and `RUSTFS_ROOT_SECRET_KEY`.
On a local PC, open `http://localhost:9101` directly.

### Data directory

`RUSTFS_DATA_DIR` (default `./data/rustfs`) holds the RustFS data. RustFS uses an internal
format: use the console or `aws s3 ls` in the `spark` container to see the objects.
`make reset` does not delete this directory. To delete the RustFS data, run `make down`,
then delete the directory.

### macOS and Windows (not verified)

- Use Docker Desktop. On Windows, keep the repository in the WSL2 filesystem (for example
  `~/iceberg-platform-poc`), not under `/mnt/c`: bind mounts on `/mnt/c` are slow.
- `LAB_UID`: on macOS use the output of `id -u`; on WSL2 the default `1000` is usually right.
- Docker Desktop gives at least 8 GB of memory to its VM: the lab needs about 6 GB with
  all catalogs on.
```

If Task 23 used the `chown` fallback, add to "Data directory": "On Linux, run
`sudo chown 10001:10001 <data directory>` once before `make up`." and remove the sentence
about the host user.

Also update the "Status" section and the "What the lab contains" table only where they say
that on-premise storage is not verified (read them first; change only those sentences).

- [ ] **Step 2: Update `NOTES.md`**

Add after D14:

```markdown
### D15 — RustFS for the on-premise variant
- The spec names MinIO or RustFS for on-premise storage. MinIO Community Edition is archived
  (2026) and is AGPLv3. The lab uses RustFS 1.0.4 (Apache-2.0): it implements STS
  `AssumeRole`, so Polaris vends credentials as on AWS.
- Rejected: Versity S3 Gateway (plain files, but no STS), SeaweedFS (too many components),
  Garage (AGPLv3), Ceph RGW (heavy, LGPL), S3Proxy (no STS).
- RustFS keeps objects in an internal format. The user accepts it: the web console shows
  the storage (user decision, 2026-10-29).
- Design: `docs/superpowers/specs/2026-10-29-rustfs-onprem-design.md`.
```

Add a finding after F5:

```markdown
### F6 — RustFS (1.0.4, checked 2026-10-29)
- RustFS ignores `RoleArn` in `AssumeRole`. The temporary credentials inherit the policies of
  the calling user (`polaris`), restricted by the Polaris session policy. The lab gives
  Polaris a placeholder role ARN with the fake account `123456789012`.
- The caller of `AssumeRole` must be a built-in user, not a service account: `rustfs-setup`
  creates the users with `rc admin user add` (rustfs/rustfs#4832).
- The lab runs RustFS with `LAB_UID` (or: the data directory must belong to uid 10001 — keep
  the sentence that matches Task 23).
- <Nessie path-style finding of Task 25, if any.>
- <Any other finding that the execution of Tasks 23-27 recorded.>
```

Replace the two placeholder lines with the facts that the controller gives you from the
reports of Tasks 23-27. If there is no such fact, delete the line.

Update the old on-premise sentences:
- F1, the line "On-premise, the default chain reads the static keys of `.env` ... Not
  tested.": replace with "On the RustFS variant, the default chain reads the keys of the user
  `lab` that `docker-compose.rustfs.yml` gives to Nessie. Tested (`make smoke-test`)."
- F5, the line "On-premise S3 for the fixture ...": replace with "On the RustFS variant,
  `CATALOG_S3_ENDPOINT` and `CATALOG_S3_PATH__STYLE__ACCESS` configure the fixture, and
  `spark/conf/s3-endpoint/baseline.conf` gives the same values to Spark (the fixture does not
  give them to clients). On AWS the lab passes no endpoint."
- "Open investigations": remove the line about Polaris credential vending on-premise; add
  "Not verified: the RustFS variant on macOS and Windows (Docker Desktop)."

- [ ] **Step 3: Update `VERSIONS.md`**

Add to the table "Components", after the Iceberg REST fixture row:

```markdown
| RustFS | 1.0.4 | `RUSTFS_IMAGE=rustfs/rustfs:1.0.4` | <https://github.com/rustfs/rustfs/releases/tag/1.0.4>, <https://hub.docker.com/r/rustfs/rustfs/tags> |
| RustFS CLI `rc` | 0.1.36 | `RUSTFS_RC_IMAGE=rustfs/rc:v0.1.36` | <https://github.com/rustfs/cli/releases>, <https://hub.docker.com/r/rustfs/rc/tags> |
```

Add a line under the table: "RustFS and `rc` were verified on 2026-10-29 (on-premise variant)."

- [ ] **Step 4: Check and commit**

```bash
make lint
grep -n 'not verified' README.md
git add README.md NOTES.md VERSIONS.md
git commit -m "docs(rustfs): document the on-premise variant with RustFS"
```

Expected: `make lint` passes; `not verified` appears only for macOS and Windows.

---

## Out of scope for this plan

- Verification on macOS and Windows.
- Multi-node RustFS, TLS, virtual-host-style addressing, clients outside the Compose network.
- `docs/HANDOFF.md`: the controller updates it on `main` after the merge.
