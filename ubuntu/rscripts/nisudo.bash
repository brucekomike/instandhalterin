#!/usr/bin/env bash
# Remote payload: grant the connecting user passwordless sudo.
# Run interactively when the user must authenticate with their sudo password.
set -euo pipefail

die() {
    echo "nisudo.bash: $*" >&2
    exit 1
}

# If invoked through sudo, target the original account rather than root.
running_user="$(id -un)"
user="$running_user"
list_user_args=()
if [[ "$running_user" == "root" && -n "${SUDO_USER:-}" ]]; then
    user="$SUDO_USER"
    list_user_args=(-U "$user")
fi
if [[ "$user" == "root" ]]; then
    echo "nisudo.bash: running as root; no sudo rule needed"
    exit 0
fi

# Keep the username safe for use in a sudoers rule and a drop-in filename.
[[ "$user" =~ ^[a-z_][a-z0-9_.-]*\$?$ ]] || die "unsupported username: $user"

# Listing privileges exposes NOPASSWD rules without mistaking a cached sudo
# authentication timestamp for passwordless permission.
if sudo -n -l "${list_user_args[@]}" 2>/dev/null | grep -q 'NOPASSWD'; then
    echo "nisudo.bash: $user already has a NOPASSWD sudo rule; skipping"
    exit 0
fi

# This may prompt when run from a terminal. Non-interactive callers must
# provide an existing sudo authorization, otherwise sudo will fail here.
if ! sudo -v; then
    die "could not authenticate sudo; run from an interactive terminal or establish sudo authorization first"
fi

sudoers="/etc/sudoers.d/90-${user}-nopasswd"
rule="$user ALL=(ALL:ALL) NOPASSWD: ALL"

if sudo -n test -e "$sudoers"; then
    if sudo -n grep -qxF -- "$rule" "$sudoers"; then
        echo "nisudo.bash: $sudoers already contains the requested rule; skipping"
        exit 0
    fi
    die "refusing to overwrite existing $sudoers"
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$rule" > "$tmp"

sudo -n visudo -cf "$tmp" >/dev/null || die "generated sudoers rule failed validation"
sudo -n install -o root -g root -m 0440 "$tmp" "$sudoers"
if ! sudo -n visudo -cf "$sudoers" >/dev/null 2>&1; then
    sudo -n rm -f "$sudoers"
    die "installed sudoers rule failed validation and was removed"
fi

echo "nisudo.bash: configured NOPASSWD:ALL for $user"
