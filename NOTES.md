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
- Why: Nessie has no credential vending and no bootstrap job, so it is the shorter path to a
  first catalog. `spark-defaults.conf` stays a static file until Phase 2, because only the
  Polaris catalog block needs secrets.

### D10 — Nessie object-store health check disabled
- Nessie 0.109.0 checks each warehouse with S3 `HeadBucket` in its readiness check.
- The VM role allows `s3:ListBucket` only with an `s3:prefix` condition (least privilege),
  so `HeadBucket` returns 403 and the readiness check reports DOWN.
- Lab: `NESSIE_CATALOG_OBJECT_STORES_HEALTH_CHECK_ENABLED=false`. The readiness check still
  covers the database connection. `tests/catalog-smoke.sh nessie` checks the S3 access.

## Findings

### F1 — Nessie S3 credentials (Nessie 0.109.0, checked 2026-10-28)
- Nessie reads and writes table metadata with its own server credentials. The lab sets
  `auth-type=APPLICATION_GLOBAL`: the AWS default credential chain, so the VM instance profile.
  The default `auth-type` is `STATIC` (static keys).
- Nessie gives clients S3 access in three ways:
  - **Request signing** (on by default): the client sends every S3 request to Nessie
    (`/iceberg/v1/{prefix}/s3sign/...`) for signing. The client needs no S3 credentials.
  - **Credential vending** with STS: `client-iam` (vended to clients) and `server-iam`
    (used by Nessie). Both are off by default. They need `assume-role` (a role ARN) and,
    outside AWS, `sts-endpoint`. The lab does not test them.
  - **Client credentials**: with request signing disabled, the client uses its own credentials.
- Lab: request signing is disabled. Spark writes the data files with the VM instance profile,
  as spec section 5.3 requires for `nessie/`. `tests/catalog-smoke.sh nessie` checks that the
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

## Open investigations

Filled in during phases 2-4.

- Polaris `relational-jdbc` bootstrap (admin tool job).
- Polaris credential vending against S3-compatible on-premise storage (`stsUnavailable`, `stsEndpoint`).
- `apache/iceberg-rest-fixture`: no tag matches Iceberg 1.11; the lab uses 1.10.1.
