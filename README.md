# iceberg-platform-poc

A reproducible lab to evaluate and compare two Apache Iceberg REST catalogs,
**Apache Polaris** and **Project Nessie**, on one Amazon EC2 VM with Docker Compose.
Data and metadata files are stored on a real AWS S3 bucket. The lab can switch to an
on-premise S3-compatible store (MinIO, RustFS) by editing `.env` only.

The lab is a test environment, not a production environment.

## Status

Work in progress. The design and the first plan are ready; the implementation starts with
the AWS scripts (Stage 1) and the Spark + Postgres stack (Phase 1).

| Document | Content |
|---|---|
| [Requirements](docs/req/prompt-agente-lab-iceberg-polaris-nessie.md) | Original requirements (Italian) |
| [Design spec](docs/superpowers/specs/2026-10-28-iceberg-catalog-lab-design.md) | Architecture, services, S3 access model, tests |
| [Plan: Stage 1 and Phase 1](docs/superpowers/plans/2026-10-28-stage1-and-phase1.md) | Task-by-task implementation plan |
| [Handoff](docs/HANDOFF.md) | Current state and decisions |

## What the lab contains

One Spark session sees the catalogs below. Each catalog writes to its own S3 prefix.

| Spark catalog | Service | S3 prefix |
|---|---|---|
| `polaris` | Apache Polaris | `s3://${S3_BUCKET}/polaris/` |
| `nessie` | Project Nessie (Iceberg REST endpoint) | `s3://${S3_BUCKET}/nessie/` |
| `rest` (optional, Compose profile `baseline`) | `apache/iceberg-rest-fixture` | `s3://${S3_BUCKET}/rest/` |

```mermaid
flowchart LR
  user([User]) -- SSH tunnel / SSM --> jupyter
  subgraph vm[EC2 VM - Docker Compose]
    jupyter[spark + JupyterLab]
    polaris[Apache Polaris]
    nessie[Project Nessie]
    rest[iceberg-rest-fixture<br/>profile baseline]
    pg[(Postgres<br/>polaris, nessie)]
    jupyter -- Iceberg REST --> polaris
    jupyter -- Iceberg REST --> nessie
    jupyter -. Iceberg REST .-> rest
    polaris --> pg
    nessie --> pg
  end
  subgraph s3[S3 bucket]
    p[polaris/]
    n[nessie/]
    r[rest/]
  end
  jupyter -- vended credentials --> p
  jupyter -- instance profile --> n
  jupyter -. instance profile .-> r
  polaris -- sts:AssumeRole --> p
  nessie -- instance profile --> n
```

The full README (prerequisites, start procedure, access through SSH and SSM, service URLs,
on-premise storage, teardown, troubleshooting) is written in the last phase of the project.

## License

Copyright 2026 the iceberg-platform-poc authors.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
