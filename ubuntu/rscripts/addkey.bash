# Remote payload for bin/rexec.sh: append the $SSHKEYS key lines to
# $HOME/.ssh/authorized_keys.
if [[ -z "${SSHKEYS:-}" ]]; then
    echo "addkey.bash: SSHKEYS is empty" >&2
    exit 1
fi
mkdir -p "$HOME/.ssh"
while IFS= read -r line; do
    if [[ -z "${line//[$' \t\r']}/" ]]; then
        continue
    fi
    printf '%s\n' "$line" >> "$HOME/.ssh/authorized_keys"
done <<< "$SSHKEYS"
