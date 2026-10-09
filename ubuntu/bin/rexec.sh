#!/bin/bash
#
# rexec.sh — run a non-interactive script on a remote host (or every host in a list).
#
# Usage:
#   rexec.sh <host> <command-file>
#   rexec.sh <host-list-file> <command-file>
#
# Every variable defined in config.sh (e.g. $REMOTE_PROXY_IP, $SSHKEYS) is
# exported to the remote shell, so the remote script can use the project
# configuration.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo $here
# Make the project configuration available to the script run remotely.
# shellcheck disable=SC1090
. "$here/config.sh"

host="${1:?usage: rexec.sh <host|host-list-file> <command-file>}"
command_file="${2:?usage: rexec.sh <host|host-list-file> <command-file>}"

# Build the remote environment prefix, quoting each value for the remote shell.
# Variables that are missing or empty in config.sh are skipped.
# NOTE: a config.sh variable is invisible to an rscript unless it is listed
# here, so add every new variable an rscript reads to this allowlist.
env_prefix=""
for var in APT_PROXY DEFAULT_PROXY SSHKEYS MAINT_USER MAINT_SSHKEYS; do
    if [[ -n "${!var-}" ]]; then
        env_prefix+=" $var=$(printf '%q' "${!var}")"
    fi
done

run_on_host() {
    ssh "$1" "$env_prefix bash -s" < "$command_file"
}

if [[ -f "$host" ]]; then
    while IFS= read -r h; do
        if [[ -z "${h//[$' \t\r']}/" ]]; then
            continue
        fi
        if [[ "$h" == \#* ]]; then
            continue
        fi
        run_on_host "$h"
    done < "$host"
else
    run_on_host "$host"
fi
