#!/bin/bash
# backup-hosts / @group tests — synthetic fixtures only, no site data.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/project/bin" "$tmp/mock-bin" "$tmp/conf/alpha" "$tmp/conf/beta" "$tmp/conf/empty"
cp "$root/bin/backup-hosts.sh" "$root/bin/rexec.sh" "$root/bin/riexec.sh" "$tmp/project/bin/"
printf 'BACKUP_CONF="%s"\n' "$tmp/conf" > "$tmp/project/config.sh"
printf '#!/bin/bash\nexit 0\n' > "$tmp/payload.bash"
touch "$tmp/conf/alpha/host-a.conf" "$tmp/conf/alpha/host-b.conf" \
      "$tmp/conf/alpha/host-c.conf.disabled" "$tmp/conf/beta/host-d.conf"

cat > "$tmp/mock-bin/ssh" <<'EOF'
#!/bin/bash
# Model ssh consuming stdin (rexec pipes the payload; riexec uses a TTY).
read -r _ || true
{
    printf 'ssh'
    printf ' <%s>' "$@"
    printf '\n'
} >> "$COMMAND_LOG"
EOF
cat > "$tmp/mock-bin/scp" <<'EOF'
#!/bin/bash
{
    printf 'scp'
    printf ' <%s>' "$@"
    printf '\n'
} >> "$COMMAND_LOG"
EOF
chmod +x "$tmp/mock-bin/ssh" "$tmp/mock-bin/scp"
export PATH="$tmp/mock-bin:$PATH" COMMAND_LOG="$tmp/commands.log"

# --- resolver -----------------------------------------------------------------
out="$(bash "$tmp/project/bin/backup-hosts.sh" alpha)"
[[ "$out" == *"host-a"* && "$out" == *"host-b"* ]]
[[ "$out" == *"# disabled: host-c"* ]]          # parked host visible, commented
[[ "$(grep -cv '^#' <<<"$out")" -eq 2 ]]        # ...and never an execution target

[[ "$(bash "$tmp/project/bin/backup-hosts.sh" --groups)" == $'alpha\nbeta\nempty' ]]
bash "$tmp/project/bin/backup-hosts.sh" "$tmp/conf/beta" | grep -Fx host-d >/dev/null
if bash "$tmp/project/bin/backup-hosts.sh" empty 2>/dev/null; then
    echo "FAIL: empty group must fail"; exit 1
fi
if bash "$tmp/project/bin/backup-hosts.sh" no-such-group 2>/dev/null; then
    echo "FAIL: unknown group must fail"; exit 1
fi

# --- rexec: @group runs exactly the active conf hosts --------------------------
: > "$COMMAND_LOG"
bash "$tmp/project/bin/rexec.sh" @alpha "$tmp/payload.bash"
[[ "$(grep -c '^ssh ' "$COMMAND_LOG")" -eq 2 ]]
grep -F '<host-a>' "$COMMAND_LOG" >/dev/null
grep -F '<host-b>' "$COMMAND_LOG" >/dev/null
if grep -F 'host-c' "$COMMAND_LOG" >/dev/null; then
    echo "FAIL: disabled host was executed"; exit 1
fi

# A conf group directory works as the target too.
: > "$COMMAND_LOG"
bash "$tmp/project/bin/rexec.sh" "$tmp/conf/beta" "$tmp/payload.bash"
grep -F '<host-d>' "$COMMAND_LOG" >/dev/null

# A bare alias stays a single host even when a group shares its name.
mkdir -p "$tmp/conf/solo" && touch "$tmp/conf/solo/other.conf"
: > "$COMMAND_LOG"
bash "$tmp/project/bin/rexec.sh" solo "$tmp/payload.bash"
[[ "$(grep -c '^ssh ' "$COMMAND_LOG")" -eq 1 ]]
grep -F '<solo>' "$COMMAND_LOG" >/dev/null

# --- riexec: @group in script mode, refused in passthrough mode ----------------
: > "$COMMAND_LOG"
bash "$tmp/project/bin/riexec.sh" @alpha "$tmp/payload.bash"
[[ "$(grep -c '^scp ' "$COMMAND_LOG")" -eq 2 ]]
[[ "$(grep -c '^ssh ' "$COMMAND_LOG")" -eq 2 ]]
if bash "$tmp/project/bin/riexec.sh" @alpha -L 2>/dev/null; then
    echo "FAIL: passthrough mode must refuse @group"; exit 1
fi

echo "backup-hosts tests passed"