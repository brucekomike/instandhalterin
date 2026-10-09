# Remote payload for bin/rexec.sh: create the $MAINT_USER maintenance account
# (default "maintainer"), grant it passwordless sudo, and append the
# $MAINT_SSHKEYS key lines — falling back to $SSHKEYS — to that new user's
# ~/.ssh/authorized_keys.
#
# Idempotent: an existing user is kept and duplicate key lines are skipped, so
# re-running against a host is a no-op. Requires the connecting operator account
# to have non-interactive sudo.
set -eu

om_die() {
    echo "om-user.bash: $*" >&2
    exit 1
}

user="${MAINT_USER:-maintainer}"
keys="${MAINT_SSHKEYS:-}"
[[ -n "$keys" ]] || keys="${SSHKEYS:-}"
[[ -n "$keys" ]] || om_die "no SSH keys: set MAINT_SSHKEYS or SSHKEYS in config.sh"

# --- account ------------------------------------------------------------
if id -u "$user" >/dev/null 2>&1; then
    echo "om-user.bash: user $user already exists"
else
    sudo -n useradd -m -s /bin/bash "$user"
    echo "om-user.bash: created user $user"
fi
sudo -n usermod -aG sudo "$user"

# --- passwordless sudo --------------------------------------------------
sudoers="/etc/sudoers.d/$user"
want="$user ALL=(ALL) NOPASSWD:ALL"
if sudo -n test -f "$sudoers" && sudo -n grep -qxF "$want" "$sudoers"; then
    echo "om-user.bash: NOPASSWD drop-in already present"
else
    sudo -n tee "$sudoers" >/dev/null << EOF
$want
EOF
    sudo -n chmod 0440 "$sudoers"
    if ! sudo -n visudo -cf "$sudoers" >/dev/null 2>&1; then
        sudo -n rm -f "$sudoers"
        om_die "sudoers drop-in $sudoers failed validation and was removed"
    fi
fi
echo "om-user.bash: sudo group + NOPASSWD configured for $user"

# --- ssh keys for the new user ------------------------------------------
home="$(getent passwd "$user" | cut -d: -f6)"
home="${home:-/home/$user}"
ssh_dir="$home/.ssh"
auth_keys="$ssh_dir/authorized_keys"

sudo -n install -d -m 700 -o "$user" -g "$user" "$ssh_dir"
sudo -n touch "$auth_keys"

added=0
while IFS= read -r line; do
    if [[ -z "${line//[$' \t\r']/}" ]]; then
        continue
    fi
    if sudo -n grep -qxF "$line" "$auth_keys"; then
        continue
    fi
    printf '%s\n' "$line" | sudo -n tee -a "$auth_keys" >/dev/null
    added=$((added + 1))
done <<< "$keys"

sudo -n chmod 600 "$auth_keys"
sudo -n chown "$user:$user" "$auth_keys"
echo "om-user.bash: $user ready, $added new key(s) added to $auth_keys"
