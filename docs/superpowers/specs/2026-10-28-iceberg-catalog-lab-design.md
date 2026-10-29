# Iceberg catalog lab (Polaris vs Nessie) — design

- Date: 2026-10-28
- Source requirements: `docs/req/prompt-agente-lab-iceberg-polaris-nessie.md` (Italian)
- Status: approved in brainstorming session

## 1. Goal

Build a reproducible Docker Compose lab on one Amazon EC2 VM. One Spark session
sees two Iceberg REST catalogs, Apache Polaris and Project Nessie, plus an
optional `apache/iceberg-rest-fixture` baseline. Data and metadata files live
on a real AWS S3 bucket. The lab must switch to an on-premise S3-compatible
store (MinIO, RustFS) by editing `.env` only. The lab is a test environment,
not production.

| Spark catalog | Service | S3 prefix |
|---|---|---|
| `polaris` | Apache Polaris | `s3://${S3_BUCKET}/polaris/` |
| `nessie` | Project Nessie (Iceberg REST endpoint) | `s3://${S3_BUCKET}/nessie/` |
| `rest` (Compose profile `baseline`) | `apache/iceberg-rest-fixture` | `s3://${S3_BUCKET}/rest/` |

## 2. Execution model

This spec, the plan and the GitHub issues were written on a developer
workstation. All implementation happens on the EC2 VM: the user clones the
repository there and runs Claude Code on the VM.

1. **Stage 1 — AWS scripts.** Claude writes `VERSIONS.md` and the `aws/`
   scripts and tests them against a stub AWS CLI. After the merge, the user runs
   `aws/setup.sh` with administrative AWS credentials in AWS CloudShell, never
   on the VM.
2. **Phases 1-6.** Claude implements each phase and runs every acceptance test
   on the VM against real S3. A phase closes only when its acceptance tests
   pass.

Facts about the environment, confirmed by the user:

- The EC2 VM already exists. It already has an IAM role (instance profile).
- Docker, the Compose plugin, the AWS CLI and Claude Code are installed on the VM.
- The user reaches the VM with SSH.
- On the VM, Claude has only the permissions of the VM role. Claude never
  creates AWS resources itself (requirement 6).

## 3. Repository

- Repository root = `iceberg-platform-poc` (the requirements name the root
  `iceberg-catalog-lab/`; the difference goes into `NOTES.md`).
- The repository is **public**. No account-specific value enters git: no
  account ID, ARN, bucket name, `externalId`, password or client secret.
  IAM documents in `aws/iam/` hold placeholders (`${ACCOUNT_ID}`,
  `${S3_BUCKET}`, `${VM_ROLE_NAME}`, `${POLARIS_EXTERNAL_ID}`) that
  `setup.sh` renders at run time.
- `.gitignore` excludes `.env` and `secrets/`.
- All repository content is in English, notebooks included.

Layout:

```text
.
├── README.md  VERSIONS.md  NOTES.md  EVALUATION.md
├── .env.example  .gitignore  docker-compose.yml  Makefile
├── aws/
│   ├── iam/vm-role-policy.json
│   ├── iam/polaris-role-policy.json
│   ├── iam/polaris-role-trust.json
│   ├── setup.sh  teardown.sh  README-aws.md
├── postgres/init/        # creates databases polaris and nessie
├── polaris/setup/        # idempotent bootstrap script
├── nessie/               # application.properties, only if env vars are not enough
├── spark/
│   ├── Dockerfile  entrypoint.sh
│   └── conf/spark-defaults.conf   # template, rendered at container start
├── scenarios/            # 11 notebooks + lab.py helper
├── tests/                # smoke tests
└── secrets/              # git-ignored, written by polaris-setup
```

## 4. AWS resources (`aws/`)

### 4.1 Parameters

`AWS_REGION`, `S3_BUCKET`, `INSTANCE_ID`, and optional `POLARIS_EXTERNAL_ID`.
When `POLARIS_EXTERNAL_ID` is absent, `setup.sh` reuses the value in the
existing `polaris-s3-access` trust policy, or generates a new one. The script
prints the values the user copies into `.env`. The VM role name is discovered
from the instance, so it is not a parameter. Templates are rendered by a
pure-bash function in `aws/lib.sh` (no `envsubst`, no extra tool).

### 4.2 `setup.sh` (idempotent)

1. Create the bucket. Enable Block Public Access (all four settings). Enable
   default encryption SSE-S3.
2. Find the VM role from `INSTANCE_ID` (instance profile → role). Put the
   inline policy `iceberg-lab-vm` on this **existing** role: S3 read/write on
   `nessie/` and `rest/`, list-only on `polaris/` (scenario 2 and the smoke
   tests list the Polaris layout; reads and writes there still need vended
   credentials), and `sts:AssumeRole` on `polaris-s3-access`. Do not touch
   other policies or the instance profile association.
3. Create the role `polaris-s3-access`. Trust policy: the VM role may call
   `sts:AssumeRole` when `sts:ExternalId` equals `POLARIS_EXTERNAL_ID`.
   Inline policy: S3 read/write/list on `polaris/` only.
4. Set the VM metadata options: `HttpTokens=required`,
   `HttpPutResponseHopLimit=2`.

Each step checks the current state first and skips or updates.

### 4.3 `teardown.sh`

1. Delete the inline policy `iceberg-lab-vm` from the VM role.
2. Delete the role `polaris-s3-access` and its inline policy.
3. Ask for confirmation (the user types the bucket name), then empty and
   delete the bucket. `setup.sh` never enables versioning, so
   `aws s3 rb --force` removes everything.
4. Print a reminder: the VM role and the hop limit stay as they are, because
   `setup.sh` did not create them.

### 4.4 Deviations from requirement 6.4

`setup.sh` does not create the VM role or the instance profile, because they
already exist. It adds an inline policy to the existing role. This goes into
`NOTES.md`.

### 4.5 `README-aws.md`

VM sizing (minimum 4 vCPU, 16 GB RAM), recommended OS, installation of Docker,
the Compose plugin and the AWS CLI, how to run `setup.sh`/`teardown.sh`, cost
notes.

## 5. Services

| Service | Image | Role |
|---|---|---|
| `postgres` | `postgres:<pinned>` | One instance. Init script creates databases `polaris` and `nessie`, each with its own user. Persistent volume. Not published on the host. |
| `polaris-bootstrap` (only if required) | `apache/polaris-admin-tool:<pinned>` | One-shot realm bootstrap for `relational-jdbc`. Idempotent. Added only if the Polaris docs require it; the deviation goes into `NOTES.md`. |
| `polaris` | `apache/polaris:<pinned>` | Iceberg REST catalog, RBAC, credential vending. Persistence `relational-jdbc`. Root credentials from `.env`. |
| `polaris-setup` | light image with `curl` and `jq` (pinned) | One-shot, idempotent. See 5.1. |
| `nessie` | `ghcr.io/projectnessie/nessie:<pinned>` | JDBC version store on database `nessie`. Iceberg REST at `/iceberg`. Warehouse `s3://${S3_BUCKET}/nessie/`. S3 access server-side with the AWS default credential chain (IMDS). No authentication. |
| `spark` | built from `spark/Dockerfile` | See 5.2. |
| `rest-fixture` (profile `baseline`) | `apache/iceberg-rest-fixture:<pinned>` | Warehouse `s3://${S3_BUCKET}/rest/`. JDBC catalog on a SQLite **file** in a volume, so the restart test passes. |

Every version is pinned in `.env`. The tag `latest` is never used.

### 5.0 Catalog selection (added 2026-10-29)

- The catalogs are off by default. Each catalog is a Compose profile:
  `polaris` (`polaris-bootstrap`, `polaris`, `polaris-setup`), `nessie` (`nessie`)
  and `baseline` (`rest-fixture`). `postgres` and `spark` have no profile, so they
  always start.
- The user chooses the catalogs with `COMPOSE_PROFILES` in `.env`, for example
  `COMPOSE_PROFILES=nessie`. Compose reads this variable itself, so `make up` and a
  plain `docker compose up` give the same result. `.env.example` leaves it empty.
- The lab must contain every catalog, but the catalogs do not have to run together.
  The tests and the scenarios need one catalog at a time.
- `make up` also stops the services of the catalogs that are not in
  `COMPOSE_PROFILES`, so the running services always match `.env`.
- Stopping a catalog keeps its data: its Postgres database and its S3 prefix stay.

### 5.1 `polaris-setup`

1. Get a token as `root`.
2. Create when missing (HTTP 409 on create counts as "already present"):
   - catalog `lab_catalog`: `storageConfigInfo` type S3, `roleArn` of
     `polaris-s3-access`, `externalId`, allowed location and default base
     location `s3://${S3_BUCKET}/polaris/`, region, and the S3 endpoint /
     path-style options when the Polaris version supports them;
   - principal `spark_user`;
   - principal role `spark_role`, granted to `spark_user`;
   - catalog role `lab_admin` on `lab_catalog` with the privileges Spark needs
     (`CATALOG_MANAGE_CONTENT`), granted to `spark_role`.
3. Write `secrets/spark_user.env` (client id and secret). When the principal
   exists and the file is missing, rotate the principal credentials and write
   the file again.

### 5.2 Spark image

- Base: official `apache/spark:<pinned>-python3` image (ASF).
- Download `iceberg-spark-runtime` and `iceberg-aws-bundle` from Maven Central;
  verify the published SHA checksum.
- `pip install` pinned JupyterLab, PyIceberg, pandas, pyarrow, requests
  (`spark/requirements.txt`). PySpark comes with the base image. Python is the
  base image's 3.10 (user decision; see `NOTES.md`).
- Iceberg client version: 1.11.0, the version Polaris and Nessie are built
  against (user decision; see `VERSIONS.md`).
- Install AWS CLI v2 (scenario 2 uses `aws s3 ls`).
- `spark/conf/spark-defaults.conf` is a template with `${VAR}` placeholders.
  `entrypoint.sh` renders it with a pure-bash placeholder substitution (same
  approach as `aws/lib.sh`) from the environment and from
  `secrets/spark_user.env`, then starts JupyterLab. It renders the block of a
  catalog only when the catalog profile is in `COMPOSE_PROFILES` (section 5.0).
- `spark.sql.extensions` = `org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions`.
- Catalog `polaris`: `type=rest`, Polaris catalog API URI, `warehouse=lab_catalog`,
  OAuth2 client credentials of `spark_user` (never `root`), scope
  `PRINCIPAL_ROLE:ALL`, header `X-Iceberg-Access-Delegation=vended-credentials`.
- Catalog `nessie`: `type=rest`, Nessie Iceberg REST URI with the `main` branch
  as prefix/reference.
- Catalog `rest`: rendered only when the `baseline` profile is active.
- `depends_on`: `polaris-setup` with `service_completed_successfully`, and
  `nessie` healthy, both with `required: false`, so `spark` starts also when a
  catalog is off.

### 5.3 S3 access model

| Prefix | Writers | Credentials |
|---|---|---|
| `polaris/` | Spark FileIO, Polaris | Only credentials **vended** by Polaris through `polaris-s3-access`. The VM role can only list `polaris/`, never read or write it, so a successful write proves that vending works. |
| `nessie/` | Spark FileIO, Nessie | VM role through IMDSv2 |
| `rest/` | Spark FileIO, rest-fixture | VM role through IMDSv2 |

Nessie credential vending (STS assume-role) is investigated in the Nessie docs.
The result goes into `NOTES.md`. Default configuration: no vending.

### 5.4 Network

- Host ports bound to `127.0.0.1` only: JupyterLab 8888, Spark UI 4040,
  Polaris 8181 (API) and 8182 (management), Nessie 19120 and its management
  port, rest-fixture (profile `baseline`).
- Access from the user's machine: SSH tunnel (primary) and SSM port
  forwarding (alternative). Both are documented in the README.
- Security group: port 22 from the user's IP only, or no inbound port with SSM.
  Documented, not managed by the scripts.

### 5.5 S3 portability

`.env` holds `S3_ENDPOINT` (empty = AWS), `AWS_REGION`, `S3_PATH_STYLE_ACCESS`,
and optional static keys `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (empty
on AWS, required on-premise where there is no IMDS). Every service reads only
these variables. Polaris credential vending against MinIO/RustFS (STS endpoint
or vending disabled) is checked in the Polaris docs; the procedure goes into
the README and the findings into `NOTES.md`.

## 6. Tests

All tests are bash scripts that run `spark-sql`, PySpark or the AWS CLI inside
the `spark` container.

- `tests/s3-access.sh` (phase 1): write, read and delete an object in
  `s3://${S3_BUCKET}/rest/_smoke/` with IMDS credentials. Negative check: a
  write to `polaris/` fails with `AccessDenied`. The requirement says
  "a test file in `s3://${S3_BUCKET}/`"; the VM role has no access to the
  bucket root, so the test uses an allowed prefix (noted in `NOTES.md`).
- `tests/catalog-smoke.sh <catalog>` (phases 2-4): create a namespace and a
  table, insert rows, read them, check that the files are under the expected
  prefix (`aws s3 ls`), run `docker compose restart`, check that the table and
  rows still exist.
- `make smoke-test`: `s3-access`, then `catalog-smoke` on each catalog in
  `COMPOSE_PROFILES`. With no catalog on, it runs `s3-access` only and says so.
- `make lint`: `bash -n` on scripts, `docker compose config`, `jq` validation of
  JSON files. No shellcheck (GPLv3, see CLAUDE.md rule 5).
- No GitHub Actions CI: the tests need real AWS.

## 7. Scenarios

- One notebook per scenario: `scenarios/01-basic-cycle.ipynb` …
  `scenarios/11-second-client.ipynb`, as listed in requirement phase 5.
- `scenarios/lab.py`: runs the SQL of a scenario on the catalog that is on and
  shows the result (pandas), with success or error. To compare the catalogs, the
  user runs the same notebook once per catalog.
- Each notebook is idempotent: it drops the objects it creates at the start.
- Scenario 6 uses the native Nessie REST API (`requests`).
- Scenario 7 creates the read-only principal `reader_user` in Polaris and shows
  that a write fails.
- `make scenarios` runs every notebook headless with
  `jupyter nbconvert --execute` (completion criterion 10.3).

## 8. Makefile

Targets: `up`, `down`, `reset` (removes volumes), `smoke-test`,
`logs`, `sql-polaris`, `sql-nessie`, `sql-rest`, `lint`, `scenarios`.
There is no `up-baseline`: the user adds `baseline` to `COMPOSE_PROFILES`
(section 5.0; deviation in `NOTES.md`).

## 9. Documentation

- `VERSIONS.md`: every pinned version, source link, compatibility matrix
  (Spark ↔ Iceberg runtime ↔ Polaris ↔ Nessie ↔ PyIceberg), verification date.
  Selection rule: the newest Spark line supported by the Iceberg runtime and
  usable with both Polaris and Nessie.
- `NOTES.md`: every deviation from the requirements and every conflict between
  the requirements and project docs.
- `EVALUATION.md`: Polaris/Nessie comparison on the eight criteria of
  requirement phase 6. Observed facts kept separate from documentation facts,
  sources cited, verification date for governance data.
- `README.md`: the eight items of requirement section 9, with a Mermaid
  architecture diagram.

## 10. Work organization

- One sprint: GitHub milestone "S1 — Iceberg catalog lab". One issue per plan
  task, with a checklist.
- This spec and the first plan are committed directly to `main` (repository
  bootstrap). After that, every change goes through a branch and a PR; the user
  merges.
- PR grouping:
  1. Stage 1: scaffolding, `VERSIONS.md`, `aws/` scripts.
  2. Stage 2: one PR per phase (1 Spark + Postgres, 2 Polaris, 3 Nessie,
     4 baseline, 5 scenarios, 6 evaluation + README).
- Planning granularity: a detailed plan for stage 1 and phase 1 now. A separate
  plan per later phase, written on the VM after the versions are verified,
  because the real versions change configuration details.

## 11. Completion criteria

As in requirement section 10: `make up` starts cleanly on a fresh VM;
`make smoke-test` passes on each catalog that is on, run at least once with
`polaris` on and once with `nessie` on; all scenario notebooks run
end to end; no credential in git; `VERSIONS.md`, `NOTES.md`, `EVALUATION.md`
are filled; `aws/teardown.sh` removes every resource `setup.sh` created.
