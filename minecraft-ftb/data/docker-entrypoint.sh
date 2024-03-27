#!/bin/bash
set -e

function check_environment() {
    mandatory=(
        "FTB_MODPACK_ID"
        "FTB_MODPACK_VERSION_ID"
        "ACCEPT_MOJANG_EULA"
    )

    missing=false
    for value in "${mandatory[@]}"
    do
        if [ -z "${!value}" ]; then
            missing=true
            echo "Missing mandatory environment variable: '$value'"
        fi
    done

    if [ "$missing" = true ]; then
        exit 1
    fi
}

function patch_start_script() {
    # We have to make sure the `start.sh` script uses `exec` to launch the server. SIGINT and
    # other signals would not be forwarded to the Java process otherwise.

    regex='^("jre/.+/bin/java" .+ nogui)$'
    output=""
    success=false

    while IFS="" read -r line || [ -n "$line" ]
    do
        if [[ $line =~ $regex ]]; then
            output+="exec "
            success=true
        fi

        output+="$line\n"
    done < start.sh

    if [ ! success ]; then
        echo "ERROR: Failed to patch 'start.sh' script."
        exit 1
    fi

    printf "$output" > start.sh
}

function get_and_run_installer() {
    pack_url="https://api.modpacks.ch/public/modpack/${FTB_MODPACK_ID}/${FTB_MODPACK_VERSION_ID}/server/linux"
    pack_installer="serverinstall_${FTB_MODPACK_ID}_${FTB_MODPACK_VERSION_ID}"

    # Adjust permissions for 'minecraft' directory
    chown -R minecraft:minecraft /var/lib/minecraft
    chmod 0700 /var/lib/minecraft

    # Download the installer
    curl -o "$pack_installer" "$pack_url"
    chmod +x "$pack_installer"

    # Install- or update the modpack
    "./$pack_installer" --auto
    rm "$pack_installer"

    # Patch start script
    patch_start_script

    # Adjust permissions for files in 'minecraft' directory
    chown -R minecraft:minecraft /var/lib/minecraft
}

function confirm() {
    read -r -p "Do you want to continue? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
    then
        return 0
    else
        return 1
    fi
}

if [ "$1" = "/var/lib/minecraft/start.sh" ]; then
    check_environment

    local_pack_id=0
    local_version_id=0

    if [ -f version.json ]; then
        local_pack_id=$(jq '.parent' version.json)
        local_version_id=$(jq '.id' version.json)

        if [ -z "$local_pack_id" ] || [ -z "$local_version_id" ]; then
            echo "ERROR: A modpack is already installed, but the 'version.json' could not be parsed."
            exit 1
        fi
    fi

    if [ "$local_pack_id" -eq 0 ]; then
        echo "INFO: Installing modpack '$FTB_MODPACK_ID' ..."

        if [ $(ls -A . | wc -l) -ne 0 ]; then
            echo "WARN: The destination directory is not empty. Continuing the process could lead to data loss."
            if ! confirm; then
                exit 0
            fi
        fi

        get_and_run_installer
        local_pack_id="$FTB_MODPACK_ID"
        local_version_id="$FTB_MODPACK_VERSION_ID"
    fi

    if [ "$local_pack_id" -ne "$FTB_MODPACK_ID" ]; then
        echo "ERROR: The installed modpack '$local_pack_id' does not match the configured modpack id '$FTB_MODPACK_ID'."
        exit 1
    fi

    if [ "$local_version_id" -ne "$FTB_MODPACK_VERSION_ID" ]; then
        echo "INFO: The requested modpack version ('$FTB_MODPACK_VERSION_ID') does not match the locally installed version ('$local_version_id')."

        if [ "$local_version_id" -lt "$FTB_MODPACK_VERSION_ID" ]; then
            echo "INFO: Upgrading modpack ..."
        else
            echo "INFO: Downgrading modpack ..."
        fi

        echo "WARN: Please make sure you have a backup before you continue."
        if ! confirm; then
            exit 0
        fi

        get_and_run_installer
    fi

    if [ ! -f eula.txt ] && [ "$ACCEPT_MOJANG_EULA" -eq 1 ]; then
        printf "eula=true\n" > eula.txt
        chown minecraft:minecraft eula.txt
    fi

    # TODO: Set- or update memory arguments in user_jvm_args.txt
fi

# Execute command on behalf of the 'minecraft' user
exec setpriv --reuid=minecraft --regid=minecraft --init-groups --reset-env "$@"
