#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

docker run -it --rm --name minecraft-ftb \
    -v "$SCRIPT_DIR/volume:/var/lib/minecraft" \
    flobernd/minecraft-ftb \
    /bin/bash
