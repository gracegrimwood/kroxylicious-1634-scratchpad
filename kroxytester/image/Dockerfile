FROM docker.io/apache/kafka:3.8.1

WORKDIR /opt/kroxytester/

USER root
COPY --chmod=755 --chown=appuser:appuser kroxytester.sh /opt/kroxytester/

USER appuser

ENTRYPOINT ./kroxytester.sh