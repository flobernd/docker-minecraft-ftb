#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

docker run -it --rm --name minecraft-ftb \
    -v "$SCRIPT_DIR/volume:/var/lib/minecraft" \
    -e "FTB_MODPACK_ID=119" \
    -e "FTB_MODPACK_VERSION_ID=11614" \
    -e "ACCEPT_MOJANG_EULA=1" \
    -p "25565:25565" \
    --stop-timeout=60 \
    flobernd/minecraft-ftb
