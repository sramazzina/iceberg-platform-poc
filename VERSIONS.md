# Versions

Verification date: 2026-10-28. Every value is pinned in `.env.example`
(image tags, JAR versions, checksums) or in `spark/requirements.txt` (Python packages).
The tag `latest` is never used.

## Components

| Component | Version | Pinned in | Source |
|---|---|---|---|
| Apache Spark | 4.1.3 (Scala 2.13, Java 17) | `SPARK_BASE_IMAGE=apache/spark:4.1.3-scala2.13-java17-python3-ubuntu` | <https://hub.docker.com/r/apache/spark/tags>, <https://github.com/apache/spark-docker/tree/master/4.1.3/scala2.13-java17-python3-ubuntu> |
| Apache Iceberg Spark runtime | 1.11.0 | `ICEBERG_SPARK_RUNTIME_ARTIFACT=iceberg-spark-runtime-4.1_2.13`, `ICEBERG_VERSION`, `ICEBERG_SPARK_RUNTIME_SHA1` | <https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-4.1_2.13/1.11.0/> |
| Apache Iceberg AWS bundle | 1.11.0 | `ICEBERG_VERSION`, `ICEBERG_AWS_BUNDLE_SHA1` | <https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/1.11.0/> |
| Apache Polaris | 1.8.0 | `POLARIS_IMAGE=apache/polaris:1.8.0` | <https://github.com/apache/polaris/releases/tag/apache-polaris-1.8.0> |
| Apache Polaris admin tool | 1.8.0 | `POLARIS_ADMIN_TOOL_IMAGE=apache/polaris-admin-tool:1.8.0` | <https://hub.docker.com/r/apache/polaris-admin-tool/tags> |
| Project Nessie | 0.109.0 | `NESSIE_IMAGE=ghcr.io/projectnessie/nessie:0.109.0` | <https://github.com/projectnessie/nessie/releases/tag/nessie-0.109.0> |
| Iceberg REST fixture | 1.10.1 | `REST_FIXTURE_IMAGE=apache/iceberg-rest-fixture:1.10.1` | <https://hub.docker.com/r/apache/iceberg-rest-fixture/tags> |
| PostgreSQL | 18.6 | `POSTGRES_IMAGE=postgres:18.6` | <https://hub.docker.com/_/postgres> |
| curl + jq job image | alpine/curl 8.22.0 (jq added with `apk`) | `POLARIS_SETUP_IMAGE=alpine/curl:8.22.0` | <https://hub.docker.com/r/alpine/curl/tags> |
| AWS CLI v2 | 2.39.0 | `AWSCLI_VERSION` | <https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst> |
| Python (Spark image) | 3.10 (Ubuntu 22.04 package) | base image | <https://github.com/apache/spark-docker/tree/master/4.1.3/scala2.13-java17-python3-ubuntu> |
| JupyterLab | 4.6.4 | `spark/requirements.txt` | <https://pypi.org/project/jupyterlab/4.6.4/> |
| PyIceberg | 0.12.0 | `spark/requirements.txt` | <https://pypi.org/project/pyiceberg/0.12.0/> |
| pandas | 2.3.3 (last release for Python 3.10) | `spark/requirements.txt` | <https://pypi.org/project/pandas/2.3.3/> |
| pyarrow | 25.0.1 (last release for Python 3.10) | `spark/requirements.txt` | <https://pypi.org/project/pyarrow/25.0.1/> |
| requests | 2.34.2 | `spark/requirements.txt` | <https://pypi.org/project/requests/2.34.2/> |

## Compatibility

| Check | Result | Source |
|---|---|---|
| Iceberg 1.11.0 ships a runtime for Spark 4.1 / Scala 2.13 | Yes | <https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-4.1_2.13/maven-metadata.xml> |
| Newest Spark line with an Iceberg runtime on Maven Central | 4.1 (no `iceberg-spark-runtime-4.2_2.13` artifact) | <https://repo1.maven.org/maven2/org/apache/iceberg/> |
| Iceberg version Polaris 1.8.0 is built against | 1.11.0 | <https://github.com/apache/polaris/blob/apache-polaris-1.8.0/gradle/libs.versions.toml> |
| Iceberg version Nessie 0.109.0 is built against | 1.11.0 | <https://github.com/projectnessie/nessie/blob/nessie-0.109.0/gradle/libs.versions.toml> |
| Spark versions the Polaris Spark plugin targets | 3.5, 4.0 (not 4.1). The lab uses the plain Iceberg REST client, not the Polaris plugin | same Polaris file |
| Postgres version used in the Polaris JDBC guide | 18.6 | <https://github.com/apache/polaris/blob/apache-polaris-1.8.0/site/content/guides/assets/postgres/docker-compose-postgres.yml> |
| PyIceberg 0.12.0 Python requirement | `>=3.10` | <https://pypi.org/project/pyiceberg/0.12.0/> |
| JupyterLab 4.6.4 Python requirement | `>=3.10` | <https://pypi.org/project/jupyterlab/4.6.4/> |
| REST fixture tag for Iceberg 1.11 | Not published; 1.10.1 is the newest versioned tag | <https://hub.docker.com/r/apache/iceberg-rest-fixture/tags> |

Polaris and Nessie do not document tests with Spark 4.1. They are used through the Iceberg
REST protocol with the same Iceberg version they are built against. The smoke tests of
phases 2 and 3 verify the combination.
