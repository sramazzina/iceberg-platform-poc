# Notes

Deviations from the requirements (`docs/req/prompt-agente-lab-iceberg-polaris-nessie.md`)
and conflicts between the requirements and the project documentation.
Each entry: what the requirement says, what the lab does, and why.

## Deviations

### D1 — Repository root name
- Requirement (section 7): the root folder is `iceberg-catalog-lab/`.
- Lab: the root is the repository `iceberg-platform-poc`.
- Why: the repository already existed with this name. The layout below the root follows section 7.

### D2 — `aws/setup.sh` uses the existing VM role
- Requirement (section 6.4): `setup.sh` creates the instance profile.
- Lab: the VM and its instance profile already exist. `setup.sh` finds the VM role
  from `INSTANCE_ID` and adds the inline policy `iceberg-lab-vm` to it.
  `teardown.sh` removes only that inline policy.
- Why: the VM was created before the lab, with its own role.

### D3 — The VM role can list `polaris/`
- Requirement (section 6.1): the VM role has S3 access to `nessie/` and `rest/`.
- Lab: the VM role can also **list** (not read, not write) `polaris/` and the bucket root.
- Why: scenario 2 and the smoke tests use `aws s3 ls` to show the Polaris layout.
  Reads and writes under `polaris/` still need credentials vended by Polaris.

### D4 — Phase 1 test object prefix
- Requirement (phase 1): read and write a test file in `s3://${S3_BUCKET}/`.
- Lab: the test writes under `s3://${S3_BUCKET}/rest/_smoke/`.
- Why: the VM role has no write access to the bucket root (least privilege).

### D5 — Python packages are pinned in `spark/requirements.txt`
- Requirement (rule 4.2): pin every version in `.env`.
- Lab: image tags and JAR versions are in `.env`; Python packages are in `spark/requirements.txt`.
- Why: pip reads a requirements file natively; one build argument per package would add noise.

### D6 — Python 3.10 in the Spark image
- The official `apache/spark:4.1.3` images are based on Ubuntu 22.04, so Python is 3.10.
  Python 3.10 reached end of life in October 2026. pandas and pyarrow are pinned to the
  last releases that support Python 3.10 (2.3.3 and 25.0.1). Accepted for a test lab.

### D7 — Iceberg client 1.11.0, not the latest 1.12.0
- Polaris 1.8.0 and Nessie 0.109.0 are built against Iceberg 1.11.0. The lab uses the same
  client version, so that compatibility is not a variable in the comparison.

### D8 — `teardown.sh` keeps the IMDS hop limit
- Requirement (section 6.5): `teardown.sh` removes everything that `setup.sh` created.
- Lab: `setup.sh` sets the hop limit of the existing VM to 2. `teardown.sh` does not set it
  back. It prints the command that restores hop limit 1.
- Why: `setup.sh` changes a setting of a VM that it did not create. The previous value is
  not recorded, so the script cannot restore it safely.

### D9 — Phase 3 (Nessie) before Phase 2 (Polaris)
- Requirement (section 8): the phases run in the order 2 (Polaris), 3 (Nessie), 4 (baseline).
- Lab: Phase 3 runs before Phase 2 (user decision, 2026-10-28).
- Why: Nessie needs no credential vending and no bootstrap job, so it is the shorter path to a
  first catalog. `spark-defaults.conf` stays a static file until Phase 2, because only the
  Polaris catalog block needs secrets.

### D10 — Nessie object-store health check disabled
- Nessie 0.109.0 checks each warehouse with S3 `HeadBucket` in its readiness check.
- The VM role allows `s3:ListBucket` only with an `s3:prefix` condition (least privilege),
  so `HeadBucket` returns 403 and the readiness check reports DOWN.
- Lab: `NESSIE_CATALOG_OBJECT_STORES_HEALTH_CHECK_ENABLED=false`. The object-store check stays
  in the readiness check, but it reports UP without an S3 call. The readiness check still
  covers the database connection. `tests/catalog-smoke.sh nessie` checks the S3 access.

### D11 — The catalogs are optional
- Requirement (sections 5.1 and 7): the stack has the services `polaris` and `nessie`, and the
  Makefile has the target `up-baseline`.
- Lab: each catalog is a Compose profile (`polaris`, `nessie`, later `baseline`). The catalogs
  are off by default. `COMPOSE_PROFILES` in `.env` selects them. There is no `up-baseline`: add
  `baseline` to `COMPOSE_PROFILES`.
- Why: user decision (2026-10-29). The user chooses the catalog for each test. The catalogs do
  not have to run together. The requirements were changed to match.

### D12 — `polaris-bootstrap` is required
- Spec (section 5): add `polaris-bootstrap` only if the Polaris docs require it.
- Lab: Polaris 1.8.0 with `relational-jdbc` does not create its tables. The admin tool creates
  them and the root principal. A second run skips, so the job runs on every `make up`.
- The job reads the root credentials from a private file (`bootstrap -f`), not from the command
  line: the image entrypoint (`run-java.sh`) writes the full command line to the log.

### D13 — `polaris-setup` reads JSON with `sed`
- Requirement (section 5.1): the setup image has `curl` and `jq`.
- Lab: the pinned image `alpine/curl` has no `jq`. The script is POSIX `sh` and reads the few
  JSON fields it needs with `sed`.
- Why: `apk add jq` at every start needs network access and installs an unpinned version.

## Findings

### F1 — Nessie S3 credentials (Nessie 0.109.0, checked 2026-10-28)
- Nessie reads and writes table metadata with its own server credentials. The lab sets
  `auth-type=APPLICATION_GLOBAL`. This uses the AWS default credential chain, which gives the
  VM instance profile. The default `auth-type` is `STATIC` (static keys).
- On-premise, the default chain reads the static keys of `.env` (`AWS_ACCESS_KEY_ID`,
  `AWS_SECRET_ACCESS_KEY`), which `docker-compose.yml` gives to Nessie. Not tested.
- Nessie gives clients S3 access in three ways:
  - **Request signing** (on by default): the client sends every S3 request to Nessie
    (`/iceberg/v1/{prefix}/s3sign/...`) for signing. The client needs no S3 credentials.
  - **Credential vending** with STS: `client-iam` (vended to clients) and `server-iam`
    (used by Nessie). Both are off by default. They need `assume-role` (a role ARN) and,
    outside AWS, `sts-endpoint`. The lab does not test them.
  - **Client credentials**: with request signing disabled, the client uses its own credentials.
- Lab: request signing is disabled. Spark writes the data and manifest files with the VM
  instance profile, as spec section 5.3 requires for `nessie/`. Nessie writes the table
  metadata files (`*.metadata.json`). `tests/catalog-smoke.sh nessie` checks that the
  Nessie log has no `s3sign` request.
- Sources: `S3BucketOptions.java`, `S3Iam.java`, `S3ClientIam.java`, `S3ServerIam.java` and
  `site/docs/guides/iceberg-rest.md` at tag `nessie-0.109.0`.

### F2 — Nessie runs without authentication
- Nessie 0.109.0 has authentication and authorization off by default
  (`nessie.server.authentication.enabled=false`). At start it logs a warning:
  "Both authentication (AuthN) and authorization (AuthZ) are disabled".
- Lab: the warning is expected. The Nessie ports are published on `127.0.0.1` only, and the
  user reaches them through an SSH or SSM tunnel. Scenario 7 documents the Nessie
  authorization model.

### F3 — Polaris purge (Polaris 1.8.0, checked 2026-10-29)
- The catalog property `polaris.config.drop-with-purge.enabled` (default false) controls the
  server-side purge: a REST `DELETE ...?purgeRequested=true` gets HTTP 403 when it is false.
- Spark `DROP TABLE ... PURGE` does not use the server-side purge. Spark deletes the files
  itself, with the S3 credentials that Polaris vends. It works also when the property is false.
- Lab: the property stays false. `tests/catalog-smoke.sh polaris` drops its table with
  `DROP TABLE ... PURGE` and fails when a file is left under `polaris/`. The VM role cannot
  delete under `polaris/`: a left file must be removed from CloudShell.

### F4 — Where the Polaris secrets are
- The root client secret is in `.env` and in the environment of the one-shot containers
  `polaris-bootstrap` and `polaris-setup` (`docker inspect` shows it). It is not in a log or
  on a command line; `tests/polaris-service.sh` checks the bootstrap log.
- The `spark_user` credentials are in `secrets/spark_user.env` (git-ignored, mode 600). The
  Spark entrypoint reads them without exporting them and writes them into
  `/opt/spark/conf/spark-defaults.conf` (mode 600). `spark.redaction.regex` hides them in the
  Spark UI.
- Accepted for a single-user lab VM, where Docker access already gives root access.

## Open investigations

Filled in during phases 2-4.

- Polaris credential vending against S3-compatible on-premise storage (`stsUnavailable`, `stsEndpoint`).
- `apache/iceberg-rest-fixture`: no tag matches Iceberg 1.11; the lab uses 1.10.1.
