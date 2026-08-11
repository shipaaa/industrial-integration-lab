FROM alpine:3.22 AS jdbc

ARG POSTGRES_JDBC_VERSION=42.7.13

RUN wget -q \
      "https://repo1.maven.org/maven2/org/postgresql/postgresql/${POSTGRES_JDBC_VERSION}/postgresql-${POSTGRES_JDBC_VERSION}.jar" \
      -O /tmp/postgresql.jar \
    && wget -q \
      "https://repo1.maven.org/maven2/org/postgresql/postgresql/${POSTGRES_JDBC_VERSION}/postgresql-${POSTGRES_JDBC_VERSION}.jar.sha1" \
      -O /tmp/postgresql.jar.sha1 \
    && cd /tmp \
    && echo "$(cat postgresql.jar.sha1)  postgresql.jar" | sha1sum -c -

FROM apache/nifi:2.10.0

ARG POSTGRES_JDBC_VERSION=42.7.13

COPY --from=jdbc --chown=nifi:nifi \
  /tmp/postgresql.jar \
  /opt/nifi/nifi-current/lib/postgresql-${POSTGRES_JDBC_VERSION}.jar
