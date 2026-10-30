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
- Lab: each catalog is a Compose profile (`polaris`, `nessie`, `baseline`). The catalogs
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

### D14 — Phases 5 and 6 deferred
- Requirement (section 8): Phase 5 writes the scenario notebooks and Phase 6 writes
  `EVALUATION.md`. Section 10 lists both as completion criteria.
- Lab: Phases 5 and 6 are deferred to a later stage (user decision, 2026-10-29). The lab has
  no scenario notebooks, no `make scenarios` and no `EVALUATION.md`.
- Why: the current scope is to build the platform for study, not to compare the catalogs.

### D15 — RustFS for the on-premise variant
- The spec names MinIO or RustFS for on-premise storage. MinIO Community Edition is archived
  (2026) and is AGPLv3. The lab uses RustFS 1.0.4 (Apache-2.0): it implements STS
  `AssumeRole`, so Polaris vends credentials as on AWS.
- Rejected: Versity S3 Gateway (plain files, but no STS), SeaweedFS (too many components),
  Garage (AGPLv3), Ceph RGW (heavy, LGPL), S3Proxy (no STS).
- RustFS keeps objects in an internal format. The user accepts it: the web console shows
  the storage (user decision, 2026-10-29).
- Design: `docs/superpowers/specs/2026-10-29-rustfs-onprem-design.md`.

## Findings

### F1 — Nessie S3 credentials (Nessie 0.109.0, checked 2026-10-28)
- Nessie reads and writes table metadata with its own server credentials. The lab sets
  `auth-type=APPLICATION_GLOBAL`. This uses the AWS default credential chain, which gives the
  VM instance profile. The default `auth-type` is `STATIC` (static keys).
- On the RustFS variant, the default chain reads the keys of the user `lab` that
  `docker-compose.rustfs.yml` gives to Nessie. Tested (`make smoke-test`).
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
- The bootstrap root file `/tmp/root.yaml` (mode 600) stays in the filesystem of the exited
  `polaris-bootstrap` container until `make down` removes it.
- Accepted for a single-user lab VM, where Docker access already gives root access.

### F5 — `apache/iceberg-rest-fixture` (1.10.1, checked 2026-10-29)
- No tag matches Iceberg 1.11: the lab uses 1.10.1, the newest versioned tag. The Spark client
  is 1.11.0. The acceptance test passes with this combination.
- The default catalog is SQLite on `/tmp/iceberg_catalog.db`, which is lost when the container
  is recreated. Lab: `CATALOG_URI=jdbc:sqlite:/home/iceberg/catalog.db` on the named volume
  `rest-fixture-data`. The volume is mounted on `/home/iceberg`, the home of the image user
  `iceberg` (uid 1000): Docker gives a named volume the owner of the folder in the image. A
  folder that is not in the image (for example `/home/iceberg/data`) is owned by root, and the
  fixture cannot write it.
- The fixture listens on 8181, the host port of Polaris. Lab: host port 8183, so `polaris` and
  `baseline` can be on together.
- `GET /v1/config` gives no default to clients (`"defaults":{}`): Spark uses its own region
  (`AWS_REGION`) and the VM instance profile.
- `DROP TABLE ... PURGE`: Spark deletes the files, not the fixture. `SparkCatalog.purgeTable`
  drops the table without purge, then deletes the reachable files with the table FileIO, that
  is the VM instance profile. The fixture log shows only `JdbcCatalog - Dropped table`. This is
  the same mechanism as F3. Source:
  `spark/v4.1/spark/src/main/java/org/apache/iceberg/spark/SparkCatalog.java` at tag
  `apache-iceberg-1.11.0`. `tests/catalog-smoke.sh rest` fails when a file is left under the
  table root, and the VM role deletes it.
- On the RustFS variant, `CATALOG_S3_ENDPOINT` and `CATALOG_S3_PATH__STYLE__ACCESS` configure
  the fixture, and `spark/conf/s3-endpoint/baseline.conf` gives the same values to Spark (the
  fixture does not give them to clients). On AWS the lab passes no endpoint: an empty endpoint
  value can break `S3FileIO`.

### F6 — RustFS (1.0.4, checked 2026-10-29)
- RustFS ignores `RoleArn` in `AssumeRole`. The temporary credentials inherit the policies of
  the calling user (`polaris`), restricted by the Polaris session policy. The lab gives
  Polaris a placeholder role ARN with the fake account `123456789012`.
- The caller of `AssumeRole` must be a built-in user, not a service account: `rustfs-setup`
  creates the users with `rc admin user add` (rustfs/rustfs#4832).
- RustFS rejects a policy resource that is not an S3 ARN: `*`, `arn:aws:sts:::*`,
  `arn:aws:iam:::*` and `arn:aws:kms:...` give "invalid resource". So:
  - The `sts:AssumeRole` statement of `rustfs/setup/policy-polaris.json` has no `Resource`
    key. `AssumeRole` works with it.
  - Polaris adds a KMS statement (`arn:aws:kms:<region>:<account>:key/*`) to the session
    policy by default, and RustFS rejects the whole policy. `polaris/setup/setup.sh` sets
    `kmsUnavailable: true` in the catalog storage configuration when `S3_ENDPOINT` is set.
    Credential vending stays on. Source: `AwsStorageConfigInfo` in
    `spec/polaris-management-service.yml` at tag `apache-polaris-1.8.0`.
  - A catalog made before this change keeps its old storage configuration. Update it with
    `PUT /api/management/v1/catalogs/lab_catalog` (`currentEntityVersion` and the
    `storageConfigInfo` with `kmsUnavailable: true`).
- Nessie 0.109.0 gives `s3.path-style-access` to clients, with `s3.endpoint`. Spark needs no
  endpoint setting for the catalog `nessie`.
- The lab runs RustFS with `LAB_UID`, so the data directory belongs to the host user. The
  RustFS log warns that it cannot write `/logs`; it logs to stdout. The warning is harmless.
- `rustfs/rustfs#2766` (`DeleteObjects` and the bucket ARN) did not occur: `DROP TABLE ...
  PURGE` works on all catalogs.

### F7 — Spark Thrift Server, dbt-spark and DuckDB (checked 2026-10-30)

All checks ran on the RustFS variant (local workstation, WSL2 with Docker Desktop).

- S1: the base image `apache/spark:4.1.3-scala2.13-java17-python3-ubuntu` has
  `spark-hive-thriftserver_2.13-4.1.3.jar` and `bin/beeline`. Confirmed.
- S2: `HiveThriftServer2` starts with the lab configuration (log line `HiveThriftServer2
  started`, about 10 s). No `/tmp/metastore_db` was created: no Derby metastore in this setup.
- S3: the session key `set:hiveconf:spark.sql.defaultCatalog` sets the default catalog of a
  Thrift session. The key `spark.sql.defaultCatalog` (no prefix) is accepted but ignored
  (`current_catalog()` stays `spark_catalog`). `use:database` does not set a catalog.
  PyHive runs `USE default` when it opens a session. The `default` namespace must exist in the
  selected catalog, or the connection fails with `SCHEMA_NOT_FOUND`. dbt-spark does not pass
  the PyHive `database` argument.
- S4: Iceberg views through the REST API: supported on polaris, nessie and rest (dbt `view`
  model created, and read through a new session on all three).
- S5: DuckDB 1.5.6 `tpch`: `install_mode` is `NOT_INSTALLED`. The extension is not statically
  linked. `INSTALL tpch` downloads it to `~/.duckdb/extensions/v1.5.6/linux_amd64/`. After the
  install, `CALL dbgen(sf = 0.001)` works (`region` has 5 rows).
- S6: authentication `NOSASL`: PyHive and Hive JDBC connect with user `spark`. With the
  default authentication, beeline works but PyHive fails: `No module named 'thrift_sasl'`
  (`dbt-spark[PyHive]==1.11.0` does not install `thrift_sasl`). Start the server with
  `--hiveconf hive.server2.authentication=NOSASL`. Use `auth: NOSASL` in the dbt profile and
  `jdbc:hive2://127.0.0.1:10000/;auth=noSasl` for beeline.
- S7: `pip check` after the install of the dbt packages: `No broken requirements found.`
- S8: dbt-spark 1.11.0 `table`, `view`, `incremental` (`merge`) with `+file_format: iceberg`:
  `PASS=3` on two consecutive runs on polaris, nessie and rest (needs the `default`
  namespace, see S3). Risk: on `rest` one run (2 threads) failed with `SQLITE_BUSY` (the
  fixture uses SQLite) and every commit then failed with `500 Unknown failure` until the
  `rest-fixture` container was restarted. After the restart, 2 threads worked on `rest`.
  On nessie, `m_incr.snapshots` has 1 row after two runs (polaris and rest: 2).

## Open investigations

Filled in during the later phases.

- Not verified: the RustFS variant on Linux with Docker Engine and on macOS. The variant is
  verified on Windows (WSL2) with Docker Desktop.
