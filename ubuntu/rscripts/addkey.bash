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

# Deduplication is opt-in. Adding a key must never rewrite lines this run was
# not asked to touch: the old unconditional call replaced the whole file via
# mktemp+mv, which deleted exact-duplicate lines and changed the file's inode
# as a side effect of an append.
#
# To enable it, set ADDKEY_DEDUPE=1 in config.sh AND add the name to the
# allowlist loop in bin/rexec.sh — rexec only exports whitelisted variables, so
# an unwritten variable never reaches this payload and the safe default holds.
if [[ "${ADDKEY_DEDUPE:-0}" == "1" ]]; then
    deduplicate "$auth_file"
    echo "addkey.bash: duplicate lines collapsed (ADDKEY_DEDUPE=1)"
else
    dups="$(sort "$auth_file" | uniq -d | wc -l)"
    if [[ "$dups" -gt 0 ]]; then
        echo "addkey.bash: $dups exact duplicate line(s) present; left untouched. Re-run with ADDKEY_DEDUPE=1 to collapse."
    fi
fi
