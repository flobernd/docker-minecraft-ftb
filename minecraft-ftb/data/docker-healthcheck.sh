#!/bin/bash

# During installation/setup, no server is expected — report healthy
if [ -f /tmp/.server-installing ]; then
    exit 0
fi

# Parse actual port from server.properties, default 25565
port=25565
if [ -f /var/lib/minecraft/server.properties ]; then
    val=$(grep -oP '^server-port=\K\d+' /var/lib/minecraft/server.properties)
    if [ -n "$val" ]; then
        port=$val
    fi
fi

# Check if server is listening
echo > /dev/tcp/localhost/"$port"
