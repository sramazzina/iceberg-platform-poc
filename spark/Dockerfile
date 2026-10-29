# Spark with Apache Iceberg, the AWS CLI and JupyterLab.
# Every version comes from .env through build arguments (see VERSIONS.md).
ARG SPARK_BASE_IMAGE
FROM ${SPARK_BASE_IMAGE}

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl unzip \
 && rm -rf /var/lib/apt/lists/*

# Iceberg jars from Maven Central, checked against the pinned SHA-1.
ARG ICEBERG_VERSION
ARG ICEBERG_SPARK_RUNTIME_ARTIFACT
ARG ICEBERG_SPARK_RUNTIME_SHA1
ARG ICEBERG_AWS_BUNDLE_SHA1
RUN set -eux; \
    base=https://repo1.maven.org/maven2/org/apache/iceberg; \
    runtime="${ICEBERG_SPARK_RUNTIME_ARTIFACT}-${ICEBERG_VERSION}.jar"; \
    bundle="iceberg-aws-bundle-${ICEBERG_VERSION}.jar"; \
    curl -fsSLo "$SPARK_HOME/jars/$runtime" "$base/${ICEBERG_SPARK_RUNTIME_ARTIFACT}/${ICEBERG_VERSION}/$runtime"; \
    echo "${ICEBERG_SPARK_RUNTIME_SHA1}  $SPARK_HOME/jars/$runtime" | sha1sum -c -; \
    curl -fsSLo "$SPARK_HOME/jars/$bundle" "$base/iceberg-aws-bundle/${ICEBERG_VERSION}/$bundle"; \
    echo "${ICEBERG_AWS_BUNDLE_SHA1}  $SPARK_HOME/jars/$bundle" | sha1sum -c -

# AWS CLI v2, pinned version.
ARG AWSCLI_VERSION
RUN set -eux; \
    curl -fsSLo /tmp/awscli.zip "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m)-${AWSCLI_VERSION}.zip"; \
    unzip -q /tmp/awscli.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscli.zip; \
    aws --version

COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt && rm /tmp/requirements.txt

# Stable path to the py4j archive bundled with Spark, so the Jupyter kernel can import pyspark.
RUN ln -s "$(ls "$SPARK_HOME"/python/lib/py4j-*-src.zip)" "$SPARK_HOME/python/lib/py4j-src.zip"
ENV PYTHONPATH=/opt/spark/python:/opt/spark/python/lib/py4j-src.zip \
    PATH=/opt/spark/bin:$PATH \
    HOME=/workspace

# The spark user gets the host UID, so files saved in bind mounts stay editable on the host.
ARG LAB_UID=1000
RUN groupmod -g "$LAB_UID" spark \
 && usermod -u "$LAB_UID" -d /workspace spark \
 && mkdir -p /workspace /opt/spark/conf \
 && chown spark:spark /workspace /opt/spark/conf "$SPARK_HOME/work-dir"

# Configuration templates; the entrypoint renders /opt/spark/conf/spark-defaults.conf at start.
COPY conf/ /opt/spark/conf-templates/
COPY render.sh /usr/local/lib/lab/render.sh
COPY entrypoint.sh /usr/local/bin/lab-entrypoint.sh

USER spark
WORKDIR /workspace
EXPOSE 8888 4040
ENTRYPOINT ["/usr/local/bin/lab-entrypoint.sh"]
