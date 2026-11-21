#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/project/bin" "$tmp/mock-bin"
cp "$root/bin/riexec.sh" "$tmp/project/bin/riexec.sh"
printf 'MAINT_USER="test user"\n' > "$tmp/project/config.sh"
printf '#!/bin/bash\nexit 0\n' > "$tmp/payload.bash"

cat > "$tmp/mock-bin/scp" <<'EOF'
#!/bin/bash
{
    printf 'scp'
    printf ' <%s>' "$@"
    printf '\n'
} >> "$COMMAND_LOG"
EOF

cat > "$tmp/mock-bin/ssh" <<'EOF'
#!/bin/bash
# Model ssh consuming stdin for its interactive session.
read -r _ || true
{
    printf 'ssh'
    printf ' <%s>' "$@"
    printf '\n'
} >> "$COMMAND_LOG"
EOF

chmod +x "$tmp/mock-bin/scp" "$tmp/mock-bin/ssh"
export PATH="$tmp/mock-bin:$PATH" COMMAND_LOG="$tmp/commands.log"

# A single-host script run stages the payload before starting ssh with a TTY.
bash "$tmp/project/bin/riexec.sh" single-host "$tmp/payload.bash" 'argument with spaces'
grep -F "scp <$tmp/payload.bash> <single-host:/tmp/instandhalterin-riexec-" "$COMMAND_LOG" >/dev/null
grep -F 'ssh <-t> <single-host> <trap ' "$COMMAND_LOG" >/dev/null
grep -F 'bash /tmp/instandhalterin-riexec-' "$COMMAND_LOG" >/dev/null

# Host-list script runs are sequential and ignore blanks and comments.
printf '# comment\nhost-one\n\nhost-two' > "$tmp/hosts.txt"
: > "$COMMAND_LOG"
bash "$tmp/project/bin/riexec.sh" "$tmp/hosts.txt" "$tmp/payload.bash"
[[ "$(grep -c '^scp ' "$COMMAND_LOG")" -eq 2 ]]
[[ "$(grep -c '^ssh ' "$COMMAND_LOG")" -eq 2 ]]

# The original interactive SSH passthrough remains available.
: > "$COMMAND_LOG"
bash "$tmp/project/bin/riexec.sh" single-host -L
grep -Fx 'ssh <-t> <single-host> <-L>' "$COMMAND_LOG" >/dev/null

echo "riexec tests passed"
