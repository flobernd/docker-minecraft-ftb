# Docker Minecraft FTB

A Docker image for running [FTB](https://www.feed-the-beast.com/) Minecraft servers.

### Example

```bash
docker run -itd --rm --name minecraft-ftb \
    -v "/docker_data/minecraft:/var/lib/minecraft" \
    -e "FTB_MODPACK_ID=119" \
    -e "FTB_MODPACK_VERSION_ID=11614" \
    -e "ACCEPT_MOJANG_EULA=1" \
    -p "25565:25565" \
    --stop-timeout=60 \
    ghcr.io/flobernd/minecraft-ftb
```

> [!WARNING]
> The server process does not shut down gracefully, if no TTY is present. Please pass the `--tty`/`-t` switch (Docker) or use `tty: true` (Docker Compose).

> [!WARNING]
> It is strongly recommended to set the `stop-timeout` / `stop_grace_period` to at least `60` seconds to avoid data loss when stopping the container.

> [!NOTE]
> It is recommended to pass the `--interactive`/`-i` switch (Docker) or use `stdin_open: true` (Docker Compose) to be able to use the server console after attaching to the container.

### Docker Compose Example

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
      - "FTB_MODPACK_ID=119"
      - "FTB_MODPACK_VERSION_ID=11614"
      - "ACCEPT_MOJANG_EULA=1"
    volumes:
      - /docker_data/minecraft:/var/lib/minecraft:rw
    ports:
      - 25565:25565
```

### Environment

#### `FTB_MODPACK_ID`

The FTB modpack ID (*required*).

> [!NOTE]
> The modpack ID and the version ID are displayed on the right-hand side of the modpack info page. For example, the [Direwolf20 1.20 modpack](https://www.feed-the-beast.com/modpacks/119-ftb-presents-direwolf20-120) has the ID `119` and the latest version, as of today, is `11614`.

#### `FTB_MODPACK_VERSION_ID`

The FTB modpack version ID (*required*).

#### `ACCEPT_MOJANG_EULA`

Set `1` to automatically agree to the [Mojang EULA](https://account.mojang.com/documents/minecraft_eula).

This option enables unattended installation. Otherwise, an interactive session must be used to accept the EULA after installation.

Default: `0`.

## License

Docker Minecraft FTB is licensed under the MIT license.
