#!/bin/bash

set -o pipefail
set -e

echoerr() {
    echo "ERROR: $@" 1>&2;
}

check_environment() {
    local mandatory=(
        "FTB_MODPACK_ID"
    )

    local missing=false
    for value in "${mandatory[@]}"
    do
        if [ -z "${!value}" ]; then
            missing=true
            echoerr "Missing mandatory environment variable: '${value}'"
        fi
    done

    if [ "${missing}" = true ]; then
        return 1
    fi
}

check_tty() {
    # For some reason, the server process does not shut down gracefully, if no TTY is present ...

    if [ ! -t 0 ] ; then
        echoerr "The server process requires a TTY. Please pass the '--tty' switch (Docker) or use 'tty: true' (Docker Compose)."
        return 1
    fi
}

# $1 = modpack id
# rt = modpack info JSON payload
fetch_modpack_info() {
    local response
    response=$(curl --fail --connect-timeout 30 --max-time 30 --no-progress-meter "https://api.modpacks.ch/public/modpack/$1") || exit $?

    if [ -z "${response}" ] || [ $(echo "${response}" | jq -r '.status') != "success" ]; then
        echoerr "Failed to fetch modpack info. Please check if the modpack id [$1] is correct."
        echoerr "$(echo "${response}" | jq -r '.message')"
        return 1
    fi

    echo "${response}"
}

# $1 = modpack info JSON payload
# rt = latest modpack version id
query_latest_version_id() {
    local result=$(echo "$1" | jq -r '[.versions | sort_by(.updated) | reverse | .[] | select(.type == "Release" and .private == false) | .id][0]')

    if [ -z "${result}" ]; then
        echoerr "The selected modpack does not have a public release."
        return 1
    fi

    echo "${result}"
}

# $1 = modpack info JSON payload
# $2 = modpack version id
# rt = modpack version info JSON payload
query_version_info() {
    local result=$(echo "$1" | jq -r ".versions[] | select(.id == $2)")

    if [ -z "${result}" ]; then
        echoerr "Failed to query version info. Please check if the modpack version id [$2] is correct."
        return 1
    fi

    echo "${result}"
}

# $1 = modpack id
# $2 = modpack version id
get_and_run_installer() {
    set -e

    local pack_url="https://api.modpacks.ch/public/modpack/${1}/${2}/server/linux"
    local pack_installer="/var/lib/minecraft/serverinstall_${1}_${2}"

    # Adjust permissions for 'minecraft' directory
    chown -R minecraft:minecraft /var/lib/minecraft
    chmod 0700 /var/lib/minecraft

    # Download the installer
    curl --fail --connect-timeout 30 --max-time 30 --no-progress-meter -o "${pack_installer}" "${pack_url}"
    chmod +x "${pack_installer}"

    # Install- or update the modpack
    "${pack_installer}" --auto
    rm "${pack_installer}"

    # Patch start script
    patch_start_script

    # Adjust permissions for files in 'minecraft' directory
    chown -R minecraft:minecraft /var/lib/minecraft
}

patch_start_script() {
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
        echoerr "Failed to patch 'start.sh' script."
        echoerr "Please open an issue here: https://github.com/flobernd/docker-minecraft-ftb"
        return 1
    fi

    printf "$output" > start.sh
}

if [ "$1" = "/var/lib/minecraft/start.sh" ]; then
    check_tty
    check_environment

    local_pack_id=0
    local_version_id=0
    target_pack_id="${FTB_MODPACK_ID}"
    target_version_id="${FTB_MODPACK_VERSION_ID:=0}"

    # Parse local modpack info

    if [ -f version.json ]; then
        local_pack_id=$(jq '.parent' version.json)
        local_version_id=$(jq '.id' version.json)

        if [ -z "${local_pack_id}" ] || [ -z "${local_version_id}" ]; then
            echoerr "A modpack is already installed, but the 'version.json' could not be parsed."
            exit 1
        fi

        if [ "${local_pack_id}" -ne "${target_pack_id}" ]; then
            echoerr "A modpack is already installed, but the modpack id [${local_pack_id}] does not match the configured modpack id [${target_pack_id}]."
            exit 1
        fi
    fi

    # Fetch modpack info

    modpack_info=$(fetch_modpack_info "${target_pack_id}")
    modpack_name=$(echo "${modpack_info}" | jq -r '.name')

    echo "Selected modpack '${modpack_name}' [${target_pack_id}]"

    # Query latest version

    latest_version_id=$(query_latest_version_id "${modpack_info}")
    latest_version_info=$(query_version_info "${modpack_info}" "${latest_version_id}")
    latest_version_name=$(echo "${latest_version_info}" | jq -r '.name')

    # Determine target version

    if [ "${target_version_id}" == 0 ]; then
        if [ "${local_pack_id}" -eq 0 ] || [ "${AUTO_UPDATE}" == 1 ]; then
            target_version_id=${latest_version_id}
        else
            target_version_id=${local_version_id}
        fi
    fi

    target_version_info=$(query_version_info "${modpack_info}" "${target_version_id}")
    target_version_name=$(echo "${target_version_info}" | jq -r '.name')

    # Install modpack

    if [ "${local_pack_id}" -eq 0 ] || [ "${FORCE_REINSTALL}" == 1 ]; then
        echo "Installing modpack version '${target_version_name}' [${target_version_id}]"

        if [ "${FORCE_REINSTALL}" != 1 ] && [ $(ls -A . | wc -l) -ne 0 ]; then
            echoerr "The destination directory is not empty. Installing the modpack could lead to data loss."
            echoerr "To continue, set the 'FORCE_REINSTALL' environment variable to '1' and retry."
            exit 1
        fi

        get_and_run_installer "${target_pack_id}" "${target_version_id}"
        local_pack_id="${target_pack_id}"
        local_version_id="${target_version_id}"
    fi

    # Query local version

    local_version_info=$(query_version_info "${modpack_info}" "${local_version_id}")
    local_version_name=$(echo "${local_version_info}" | jq -r '.name')

    # Prevent modpack downgrade

    if [ "${local_version_id}" -gt "${target_version_id}" ]; then
        echoerr "Detected downgrade from version '${local_version_name}' [${local_version_id}] to '${target_version_name}' [${target_version_id}]."
        echoerr "To continue, set the 'FORCE_REINSTALL' environment variable to '1' and retry."
        exit 1
    fi

    # Upgrade modpack

    if [ "${local_version_id}" -lt "${target_version_id}" ]; then
        echo "Upgrading modpack from version '${local_version_name}' [${local_version_id}] to '${target_version_name}' [${target_version_id}]."

        get_and_run_installer "${target_pack_id}" "${target_version_id}"
        local_version_id="${target_version_id}"
        local_version_name="${target_version_name}"
    fi

    # Show info, if a newer version is available

    if [ "${local_version_id}" -lt "${latest_version_id}" ]; then
        echo "INFO: A newer version '${latest_version_name}' [${latest_version_id}] is available."
    fi

    # Accept Mojang EULA

    if [ ! -f eula.txt ] && [ "${ACCEPT_MOJANG_EULA:=0}" == 1 ]; then
        printf "eula=true\n" > eula.txt
        chown minecraft:minecraft eula.txt
    fi

    # TODO: Set- or update memory arguments in user_jvm_args.txt

    # Start modpack

    echo "Starting modpack '${modpack_name}' (${target_pack_id}) version '${local_version_name}' [${local_version_id}]"
fi

# Execute command on behalf of the 'minecraft' user
exec setpriv --reuid=minecraft --regid=minecraft --init-groups --reset-env "$@"
