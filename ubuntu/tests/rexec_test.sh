#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -f "$tmp/bin/rexec.sh" "$tmp/bin/ssh" "$tmp/config.sh" "$tmp/hosts" "$tmp/payload" "$tmp/ssh.log" "$tmp/ssh-input" "$tmp/expected"; rmdir "$tmp/bin" "$tmp"' EXIT

mkdir "$tmp/bin"
cp "$root/bin/rexec.sh" "$tmp/bin/rexec.sh"
printf 'APT_PROXY="test proxy"\n' > "$tmp/config.sh"
printf 'echo payload\n' > "$tmp/payload"
cat > "$tmp/bin/ssh" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >> "$SSH_LOG"
cat > "$SSH_INPUT"
[[ "$1" != "${FAIL_HOST-}" ]] || exit 7
EOF
chmod +x "$tmp/bin/ssh"
export PATH="$tmp/bin:$PATH" SSH_LOG="$tmp/ssh.log" SSH_INPUT="$tmp/ssh-input"

printf '\n \t\r\n# comment\nhost-one\n\nhost-two' > "$tmp/hosts"
bash "$tmp/bin/rexec.sh" "$tmp/hosts" "$tmp/payload" > /dev/null
printf 'host-one\nhost-two\n' > "$tmp/expected"
diff -u "$tmp/expected" "$tmp/ssh.log"
cmp "$tmp/payload" "$tmp/ssh-input"

: > "$tmp/ssh.log"
printf 'host-three\n# comment\n \t' > "$tmp/hosts"
bash "$tmp/bin/rexec.sh" "$tmp/hosts" "$tmp/payload" > /dev/null
printf 'host-three\n' > "$tmp/expected"
diff -u "$tmp/expected" "$tmp/ssh.log"

: > "$tmp/ssh.log"
: > "$tmp/hosts"
bash "$tmp/bin/rexec.sh" "$tmp/hosts" "$tmp/payload" > /dev/null
[[ ! -s "$tmp/ssh.log" ]]

bash "$tmp/bin/rexec.sh" single-host "$tmp/payload" > /dev/null
printf 'single-host\n' > "$tmp/expected"
diff -u "$tmp/expected" "$tmp/ssh.log"

printf 'bad-host\nlater-host\n' > "$tmp/hosts"
: > "$tmp/ssh.log"
if FAIL_HOST=bad-host bash "$tmp/bin/rexec.sh" "$tmp/hosts" "$tmp/payload" > /dev/null; then
    echo "Expected ssh failure to be propagated" >&2
    exit 1
fi
printf 'bad-host\n' > "$tmp/expected"
diff -u "$tmp/expected" "$tmp/ssh.log"

echo "rexec tests passed"
