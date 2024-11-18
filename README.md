# Docker Minecraft FTB

A Docker image developed to launch Minecraft [FTB](https://www.feed-the-beast.com/) Modpack servers as safely, quickly and easily as possible.

## Features

- Supports all "Feed The Beast" (FTB) [modpacks](https://www.feed-the-beast.com/modpacks?sort=featured)
- Configurable modpack versions
  - Allows pinning to a specific modpack version (see `FTB_MODPACK_VERSION_ID`)
  - Installs the latest version of the modpack, if no specific version is configured
- Supports automatic modpack upgrades on container start (see `AUTO_UPDATE`)
- Supports unattended installation (see `ACCEPT_MOJANG_EULA`)
- Supports configuration of user-defined JVM arguments as part of the container configuration (see `USER_JVM_ARGS`)
- Drops `root` privileges after setting up the container and runs the server as an unprivileged user

## Example

```bash
docker run -itd --name minecraft-ftb \
    -v "/docker_data/minecraft:/var/lib/minecraft" \
    -e "FTB_MODPACK_ID=126" \
    -e "ACCEPT_MOJANG_EULA=1" \
    -e "USER_JVM_ARGS=-Xms1G -Xmx4G" \
    -p "25565:25565" \
    --stop-timeout=60 \
    ghcr.io/flobernd/minecraft-ftb
```

## Docker Compose Example

```yaml
services:
  minecraft-ftb:
    image: ghcr.io/flobernd/minecraft-ftb:latest
    container_name: minecraft-ftb
    restart: unless-stopped
    tty: true
    stdin_open: true
    stop_grace_period: 1m
    environment:
      FTB_MODPACK_ID: 126
      ACCEPT_MOJANG_EULA: 1
      USER_JVM_ARGS: "-Xms1G -Xmx4G"
    volumes:
      - ./minecraft:/var/lib/minecraft:rw
    ports:
      - 25565:25565
```

## Notes

> [!WARNING]
> The server process does not shut down gracefully, if no TTY is present. Please pass the `--tty`/`-t` switch (Docker) or use `tty: true` (Docker Compose).

> [!WARNING]
> It is strongly recommended to set the `stop-timeout` (Docker) / `stop_grace_period` (Docker Compose) to at least `60` seconds to avoid data loss when stopping the container.

> [!NOTE]
> It is recommended to pass the `--interactive`/`-i` switch (Docker) or use `stdin_open: true` (Docker Compose) to be able to use the server console after attaching to the container.

## Environment

### `FTB_MODPACK_ID`

The FTB modpack ID (*required*).

> [!NOTE]
> The modpack ID and the version ID are displayed on the right-hand side of the modpack info page. For example, the [Direwolf20 1.21 modpack](https://www.feed-the-beast.com/modpacks/126-ftb-presents-direwolf20-121) has the ID `126` and the latest version, as of today, is `12599`.

### `FTB_MODPACK_VERSION_ID`

The FTB modpack version ID.

> [!NOTE]
> If the configured version is lower than the version already installed, the container will fail to start with an error.

Default: Latest version of the configured modpack.

### `ACCEPT_MOJANG_EULA`

Set `1` to automatically agree to the [Mojang EULA](https://account.mojang.com/documents/minecraft_eula).

This option enables unattended installation. Otherwise, an interactive session must be used to accept the EULA after installation, or the `eula.txt` must be edited manually and the container restarted.

Default: `0`.

### `USER_JVM_ARGS`

Optional, user-defined JVM arguments.

Use the `-Xms` switch to configure the minimum amount of memory used by the JVM. `-Xms1G` sets the minimum amount of memory to 1 GB. The `M` suffix can be used to specify the amount of memory in megabytes instead of gigabytes.

Use the `-Xmx` switch to configure the maximum amount of memory used by the JVM. `-Xms4G` sets the maximum amount of memory to 4 GB. The `M` suffix can be used to specify the amount of memory in megabytes instead of gigabytes.

To specify multiple arguments, combine them with spaces: `-Xms1G -Xmx4G`.

> [!WARNING]
> Using this option causes the `user_jvm_args.txt` file to be overwritten when the container is started.

Default: *none*

### `AUTO_UPDATE`

Set `1` to automatically update the modpack when the container is started.

If `FTB_MODPACK_VERSION_ID` is set, the configured version number is used, otherwise the latest version of the modpack is determined automatically.

Default: `0`

### `FORCE_REINSTALL`

Set `1` to force a reinstallation of the modpack when the container is started.

> [!WARNING]
> This option should only be used in special cases, as constantly reinstalling the modpack significantly slows down the start of the container.

Default: `0`

## License

Docker Minecraft FTB is licensed under the MIT license.
