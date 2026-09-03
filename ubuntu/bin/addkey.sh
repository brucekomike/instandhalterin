#!/bin/bash
#
# addkey.sh — append the SSH keys from config.sh to $HOME/.ssh/authorized_keys.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$here/config.sh" ]]; then
    echo "addkey.sh: $here/config.sh not found; run bin/configstrap.sh first" >&2
    exit 1
fi

# shellcheck disable=SC1090
. "$here/config.sh"

if [[ -z "${SSHKEYS:-}" ]]; then
    echo "addkey.sh: SSHKEYS is empty in $here/config.sh" >&2
    exit 1
fi

ssh_dir="$HOME/.ssh"
mkdir -p "$ssh_dir"

# Append each non-blank key line (drops leading/trailing newlines and CR).
while IFS= read -r line; do
    if [[ -z "${line//[$' \t\r']}/" ]]; then
        continue
    fi
    printf '%s\n' "$line" >> "$ssh_dir/authorized_keys"
done <<< "$SSHKEYS"
