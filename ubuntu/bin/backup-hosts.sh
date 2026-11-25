#!/bin/bash
#
# backup-hosts.sh — resolve host membership from a backup-scripts conf/ tree.
#
# backup-scripts keeps one conf file per host and the FILENAME IS the ssh
# target (conf/<group>/<alias>.conf, or conf/<alias>.conf for a single host).
# That makes the backup scope a host list this tool can read instead of
# maintaining a second copy: deployment runs and backup scope share one
# membership source.
#
# Usage:
#   backup-hosts.sh <group>     # aliases from conf/<group>/*.conf, sorted
#   backup-hosts.sh <dir>       # same, for an explicit conf group directory
#   backup-hosts.sh --groups    # list group names (subdirectories of conf/)
#
# The conf directory comes from $BACKUP_CONF (config.sh or environment).
# *.conf.disabled files are parked hosts: they are REPORTED as comment lines
# (consumers skip comments) so a disabled host is visible, never executed,
# and never silently absent.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1090
[[ -f "$here/config.sh" ]] && . "$here/config.sh"

conf="${BACKUP_CONF:-}"
[[ -n "$conf" && -d "$conf" ]] || {
    echo "backup-hosts.sh: BACKUP_CONF is not set to a readable directory" >&2
    echo "  set it in config.sh (or the environment) to the backup-scripts conf/ dir" >&2
    exit 1
}

if [[ "${1:-}" == "--groups" ]]; then
    find "$conf" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
    exit 0
fi

group="${1:?usage: backup-hosts.sh <group> | <dir> | --groups}"
if [[ -d "$group" ]]; then
    dir="$group"
else
    dir="$conf/$group"
fi
[[ -d "$dir" ]] || { echo "backup-hosts.sh: no group '$group' under $conf" >&2; exit 1; }

shopt -s nullglob
active=0
for f in "$dir"/*.conf; do
    basename "$f" .conf
    active=$((active+1))
done
for f in "$dir"/*.conf.disabled; do
    echo "# disabled: $(basename "$f" .conf.disabled)"
done
if [[ $active -eq 0 ]]; then
    echo "backup-hosts.sh: group '$group' has no active *.conf hosts" >&2
    exit 1
fi