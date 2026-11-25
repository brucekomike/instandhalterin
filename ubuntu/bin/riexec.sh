#!/bin/bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage:
  riexec.sh <host|host-list-file|@group> <rscript> [script-args...]
  riexec.sh <host> [ssh-args...]

@group resolves hosts from backup-scripts conf/<group>/ file names
(BACKUP_CONF in config.sh); a bare name is a single ssh alias.
EOF
    exit 2
}

[[ $# -gt 0 ]] || usage
host_arg="$1"

# Script mode is selected when the second argument names a local file. Stage
# it first so the allocated remote TTY remains available for password prompts.
if [[ $# -ge 2 && -f "$2" ]]; then
    command_file="$2"
    shift 2
    script_args=""
    for arg in "$@"; do
        script_args+=" $(printf '%q' "$arg")"
    done

    here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    [[ -f "$here/config.sh" ]] || {
        echo "riexec.sh: missing $here/config.sh; run bin/configstrap.sh first" >&2
        exit 1
    }
    # shellcheck disable=SC1090
    . "$here/config.sh"

    env_prefix=""
    for var in APT_PROXY DEFAULT_PROXY SSHKEYS MAINT_USER MAINT_SSHKEYS; do
        if [[ -n "${!var-}" ]]; then
            env_prefix+=" $var=$(printf '%q' "${!var}")"
        fi
    done

    tmp_dir="$(mktemp -d)"
    trap 'rmdir "$tmp_dir" 2>/dev/null || true' EXIT
    remote_script="/tmp/instandhalterin-riexec-${tmp_dir##*/}.bash"

    # Resolve @group / conf-group-dir into a host list file (shared membership
    # with backup-scripts: the conf filename IS the ssh target).
    if [[ "$host_arg" == @* || -d "$host_arg" ]]; then
        resolved_list="$(mktemp)"
        trap 'rm -f "$resolved_list"; rmdir "$tmp_dir" 2>/dev/null || true' EXIT
        "$here/bin/backup-hosts.sh" "${host_arg#@}" > "$resolved_list"
        host_arg="$resolved_list"
    fi

    run_script_on_host() {
        local remote_host="$1"
        echo "$remote_host"
        scp "$command_file" "$remote_host:$remote_script"
        remote_command="trap 'rm -f -- $remote_script' EXIT; chmod 700 $remote_script && $env_prefix bash $remote_script$script_args"
        ssh -t "$remote_host" "$remote_command"
    }

    if [[ -f "$host_arg" ]]; then
        while IFS= read -r remote_host <&3 || [[ -n "$remote_host" ]]; do
            [[ -n "${remote_host//[$' \t\r']/}" ]] || continue
            [[ "$remote_host" == \#* ]] && continue
            run_script_on_host "$remote_host"
        done 3< "$host_arg"
    else
        run_script_on_host "$host_arg"
    fi
    exit 0
fi

# Preserve the original interactive SSH passthrough mode.
if [[ "$host_arg" == @* ]]; then
    echo "riexec.sh: @group needs a script to run; passthrough mode takes a single host" >&2
    exit 2
fi
remote_host="$host_arg"
shift
echo "ssh -t $remote_host $*"
exec ssh -t "$remote_host" "$@"
