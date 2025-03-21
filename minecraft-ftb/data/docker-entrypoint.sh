#!/bin/bash

set -o pipefail
set -o nounset
set -e

ansi_rst="\e[0m"
ansi_b="\e[94m"
ansi_g="\e[92m"
ansi_r="\e[31m"

echoerr() {
    echo -e "${ansi_r}ERROR:${ansi_rst} $*" 1>&2;
}

echoinfo() {
    echo -e "${ansi_b}INFO:${ansi_rst} $*"
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
            echoerr "Missing mandatory environment variable: '${ansi_b}${value}${ansi_rst}'"
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

setup_minecraft_user() {
    if [ "$(id -u)" != "0" ]; then
        return 0
    fi

    requires_chown=false
    target_group_name="minecraft"
    target_user_name="minecraft"

    if getent group "${GID}" > /dev/null 2>&1; then
        group_name=$(getent group "${GID}" | cut -d: -f1)
        
        if [ "${group_name}" != "${target_group_name}" ]; then
            echoerr "The group with GID '${ansi_g}${GID}${ansi_rst}' and name '${ansi_b}${group_name}${ansi_rst}' can not be used as the 'minecraft' group."
            return 1
        fi
    else
        requires_chown=true
        groupadd \
            --gid "${GID}" \
            --system \
            "${target_group_name}"
    fi

    if getent passwd "${UID}" > /dev/null 2>&1; then
        user_name=$(getent passwd "${UID}" | cut -d: -f1)
        
        if [ "${user_name}" != "${target_user_name}" ]; then
            echoerr "The user with UID '${ansi_g}${UID}${ansi_rst}' and name '${ansi_b}${user_name}${ansi_rst}' can not be used as the 'minecraft' user."
            return 1
        fi
    else
        requires_chown=true
        useradd \
            --gid "${GID}" \
            --home-dir /var/lib/minecraft \
            --no-create-home \
            --system \
            --uid "${UID}" \
            "${target_user_name}"
    fi

    if [ $requires_chown = true ]; then
        chown -R minecraft:minecraft /var/lib/minecraft
    fi
}

# $1 = modpack id
# rt = modpack info JSON payload
fetch_modpack_info() {
    local response
    response=$(curl --fail --connect-timeout 30 --max-time 30 --no-progress-meter "https://api.feed-the-beast.com/v1/modpacks/public/modpack/$1") || exit $?

    if [ -z "${response}" ] || [ "$(echo "${response}" | jq -r '.status')" != "success" ]; then
        echoerr "Failed to fetch modpack info. Please check if the modpack id [${ansi_g}$1${ansi_rst}] is correct."
        echoerr "$(echo "${response}" | jq -r '.message')"
        return 1
    fi

    echo "${response}"
}

# $1 = modpack info JSON payload
# rt = latest modpack version id
query_latest_version_id() {
    # shellcheck disable=SC2155
    local result=$(echo "$1" | jq -r '[.versions | sort_by(.updated) | reverse | .[] | select((.type | ascii_downcase == "release") and .private == false) | .id][0]')

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
    # shellcheck disable=SC2155
    local result=$(echo "$1" | jq -r ".versions[] | select(.id == $2)")

    if [ -z "${result}" ]; then
        echoerr "Failed to query version info. Please check if the modpack version id [${ansi_g}$2${ansi_rst}] is correct."
        return 1
    fi

    echo "${result}"
}

# $1 = modpack id
# $2 = modpack version id
get_and_run_installer() {
    set -e

    # shellcheck disable=SC2155
    local architecture="$([ "$(uname -m)" == "x86_64" ] && echo "linux" || echo "arm/linux")"

    local pack_url="https://api.feed-the-beast.com/v1/modpacks/public/modpack/${1}/${2}/server/${architecture}"
    local pack_installer="/var/lib/minecraft/serverinstall_${1}_${2}"

    # Adjust permissions for 'minecraft' directory
    if [ "$(id -u)" = "0" ]; then
        chown -R minecraft:minecraft /var/lib/minecraft
        chmod 0700 /var/lib/minecraft
    fi

    # Download the installer
    local content_type
    content_type=$(curl --fail --connect-timeout 30 --max-time 30 --no-progress-meter -w '%{content_type}' -o "${pack_installer}" "${pack_url}") || return $?

    if [ "$content_type" != "application/octet-stream" ]; then
        echoerr "Failed to download the modpack installer. Unexpected response from server."

        if [ "$content_type" = "application/json" ]; then
            # shellcheck disable=SC2155
            echoerr "$(jq -r '.message' "${pack_installer}")"
        fi
        
        rm "${pack_installer}"
        return 1
    fi

    chmod +x "${pack_installer}"

    # Install- or update the modpack
    "${pack_installer}" --auto
    rm "${pack_installer}"

    # Patch start script
    patch_start_script || return $?

    # Adjust permissions for files in 'minecraft' directory
    if [ "$(id -u)" = "0" ]; then
        chown -R minecraft:minecraft /var/lib/minecraft
    fi
}

locate_start_script() {
    local path="/var/lib/minecraft"

    if [ -f "${path}/start.sh" ]; then
        echo "${path}/start.sh"
        return 0
    fi

    if [ -f "${path}/run.sh" ]; then
        echo "${path}/run.sh"
        return 0
    fi

    echoerr "Failed to locate 'start.sh' or 'run.sh' script."
    echoerr "Please open an issue here: https://github.com/flobernd/docker-minecraft-ftb"
    return 1
}

patch_start_script() {
    # We have to make sure the `start.sh` or `run.sh` script uses `exec` to launch the server.
    # SIGINT and other signals would not be forwarded to the Java process otherwise.

    local file
    file=$(locate_start_script) || return $?

    local regex='^("jre/.+/bin/java" .+ nogui)$'
    local output=""
    local success=false

    while IFS="" read -r line || [ -n "${line}" ]
    do
        if [[ $line =~ $regex ]]; then
            output+="exec "
            success=true
        fi

        output+="${line}\n"
    done < "${file}"

    if [ ! "${success}" ]; then
        echoerr "Failed to patch 'start.sh' or 'run.sh' script."
        echoerr "Please open an issue here: https://github.com/flobernd/docker-minecraft-ftb"
        return 1
    fi

    # shellcheck disable=SC2059
    printf "${output}" > "${file}"
}

update_user_jvm_args() {
    if [ -z "${USER_JVM_ARGS}" ]; then
        exit 0
    fi

    printf "# Generated by \"docker-minecraft-ftb\"; DO NOT EDIT.\n\n" > /var/lib/minecraft/user_jvm_args.txt
    printf "%s" "${USER_JVM_ARGS}" | xargs -n 1 printf "%s\n" >> /var/lib/minecraft/user_jvm_args.txt
}

if [ "$1" = "/var/lib/minecraft/start.sh" ] || [ "$1" = "/var/lib/minecraft/run.sh" ]; then
    check_tty
    check_environment
    setup_minecraft_user

    manifest_found=false
    local_pack_id=0
    local_version_id=0
    target_pack_id="${FTB_MODPACK_ID}"
    target_version_id="${FTB_MODPACK_VERSION_ID:=0}"

    # Parse local modpack info

    if [ -f /var/lib/minecraft/version.json ]; then
        local_pack_id=$(jq '.parent' /var/lib/minecraft/version.json)
        local_version_id=$(jq '.id' /var/lib/minecraft/version.json)
        manifest_found=true
    fi

    if [ -f /var/lib/minecraft/.manifest.json ]; then
        local_pack_id=$(jq '.id' /var/lib/minecraft/.manifest.json)
        local_version_id=$(jq '.versionId' /var/lib/minecraft/.manifest.json)
        manifest_found=true
    fi

    if [ $manifest_found = true ]; then
        if [ -z "${local_pack_id}" ] || [ -z "${local_version_id}" ]; then
            echoerr "A modpack is already installed, but the '.manifest.json' or version.json' could not be parsed."
            exit 1
        fi

        if [ "${local_pack_id}" -ne "${target_pack_id}" ]; then
            echoerr "A modpack is already installed, but the modpack id [${ansi_g}${local_pack_id}${ansi_rst}] does not " \
                    "match the configured modpack id [${ansi_g}${target_pack_id}${ansi_rst}]."
            exit 1
        fi
    fi

    # Fetch modpack info

    modpack_info=$(fetch_modpack_info "${target_pack_id}")
    modpack_name=$(echo "${modpack_info}" | jq -r '.name')

    echo -e "Selected modpack '${ansi_b}${modpack_name}${ansi_rst}' [${ansi_g}${target_pack_id}${ansi_rst}]"

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
        echo -e "Installing modpack version '${ansi_b}${target_version_name}${ansi_rst}' [${ansi_g}${target_version_id}${ansi_rst}]"

        # shellcheck disable=SC2012
        if [ "${FORCE_REINSTALL}" != 1 ] && [ "$(ls -A . | wc -l)" -ne 0 ]; then
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
        echoerr "Detected downgrade from version " \
                "'${ansi_b}${local_version_name}${ansi_rst}' [${ansi_g}${local_version_id}${ansi_rst}] to" \
                "'${ansi_b}${target_version_name}${ansi_rst}' [${ansi_g}${target_version_id}${ansi_rst}]."
        echoerr "To continue, set the 'FORCE_REINSTALL' environment variable to '1' and retry."
        exit 1
    fi

    # Upgrade modpack

    if [ "${local_version_id}" -lt "${target_version_id}" ]; then
        echo -e "Upgrading modpack from version " \
                "'${ansi_b}${local_version_name}${ansi_rst}' [${ansi_g}${local_version_id}${ansi_rst}] to" \
                "'${ansi_b}${target_version_name}${ansi_rst}' [${ansi_g}${target_version_id}${ansi_rst}]."

        get_and_run_installer "${target_pack_id}" "${target_version_id}"
        local_version_id="${target_version_id}"
        local_version_name="${target_version_name}"
    fi

    # Show info, if a newer version is available

    if [ "${local_version_id}" -lt "${latest_version_id}" ]; then
        echoinfo "A newer version '${ansi_b}${latest_version_name}${ansi_rst}' [${ansi_g}${latest_version_id}${ansi_rst}] is available."
    fi

    # Accept Mojang EULA

    if [ ! -f eula.txt ] && [ "${ACCEPT_MOJANG_EULA:=0}" == 1 ]; then
        printf "eula=true\n" > eula.txt
        if [ "$(id -u)" = "0" ]; then
            chown minecraft:minecraft eula.txt
        fi
    fi

    # Set- or update JVM arguments in `user_jvm_args.txt`

    update_user_jvm_args

    # Start modpack

    start_script=$(locate_start_script) || exit $?
    # Make sure to use the correct start script for the installed modpack and version
    set -- "${start_script}" "${@:2}"

    echo -e "Starting modpack '${ansi_b}${modpack_name}${ansi_rst}' [${ansi_g}${target_pack_id}${ansi_rst}]" \
            "version '${ansi_b}${local_version_name}${ansi_rst}' [${ansi_g}${local_version_id}${ansi_rst}]"
fi

 if [ "$(id -u)" = "0" ]; then
    # Execute command as the 'minecraft' user
    exec setpriv --reuid=minecraft --regid=minecraft --init-groups --reset-env "$@"
 else
    # Already running as non-root, just execute the command
     exec "$@"
 fi

