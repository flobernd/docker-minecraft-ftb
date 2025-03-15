FROM debian:bookworm-slim

# Environment

ENV UID=99
ENV GID=99
ENV FTB_MODPACK_ID=0
ENV FTB_MODPACK_VERSION_ID=0
ENV ACCEPT_MOJANG_EULA=0
ENV USER_JVM_ARGS=""
ENV AUTO_UPDATE=0
ENV FORCE_REINSTALL=0

# Set up runtime dependencies

# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        jq \
    ; \
    rm -rf /var/lib/apt/lists/*

RUN mkdir /var/lib/minecraft

# Entrypoint config

STOPSIGNAL SIGINT

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

WORKDIR /var/lib/minecraft

CMD ["/var/lib/minecraft/start.sh"]
