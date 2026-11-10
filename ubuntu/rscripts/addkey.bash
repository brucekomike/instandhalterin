# Remote payload for bin/rexec.sh: append the $SSHKEYS key lines to
# $HOME/.ssh/authorized_keys, skipping any line that already exists in the
# file, then removing duplicates left over from earlier runs or manual edits.
if [[ -z "${SSHKEYS:-}" ]]; then
    echo "addkey.bash: SSHKEYS is empty" >&2
    exit 1
fi
mkdir -p "$HOME/.ssh"
auth_file="$HOME/.ssh/authorized_keys"

deduplicate() {
    local file="$1"
    local tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    awk '!seen[$0]++' "$file" > "$tmp" && mv "$tmp" "$file"
}

while IFS= read -r line; do
    while [[ "$line" == *[$' \t\r'] ]]; do
        line="${line%[ $'\t'$'\r']}"
    done
    if [[ -z "$line" ]]; then
        continue
    fi
    if [[ -f "$auth_file" ]] && grep -Fxq -- "$line" "$auth_file"; then
        continue
    fi
    printf '%s\n' "$line" >> "$auth_file"
done <<< "$SSHKEYS"

deduplicate "$auth_file"
