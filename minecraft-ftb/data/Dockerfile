FROM debian:bookworm-slim

# Environment

ENV FTB_MODPACK_ID=0
ENV FTB_MODPACK_VERSION_ID=0
ENV ACCEPT_MOJANG_EULA=0
ENV USER_JVM_ARGS=
ENV AUTO_UPDATE=0
ENV FORCE_REINSTALL=0

# Set up runtime dependencies

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
        curl \
        jq \
	; \
    rm -rf /var/lib/apt/lists/*

# Set up container user

RUN set -eux; \
	groupadd --gid 99 --system minecraft; \
	useradd \
		--gid minecraft \
		--home-dir /var/lib/minecraft \
		--no-create-home \
		--system \
		--uid 99 \
		minecraft \
	; \
	mkdir /var/lib/minecraft; \
	chown minecraft:minecraft /var/lib/minecraft

# Entrypoint config

STOPSIGNAL SIGINT

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

WORKDIR /var/lib/minecraft

CMD ["/var/lib/minecraft/start.sh"]
