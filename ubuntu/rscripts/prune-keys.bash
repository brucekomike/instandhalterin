# Remote payload for bin/rexec.sh: revoke EXPLICIT public keys by fingerprint.
#
# This is the missing half of the key story. addkey.bash only ever adds, so the
# fleet had no way to act on a rotated or decommissioned key: the stale
# wfp@DESKTOP-JELNNPK key (SHA256:WngWVGo+...) was measured live on 22 hosts on
# 2026-11-24 alongside the current one, and nothing in this repo could remove it.
#
# Revocation is the owner's decision. This tool only makes it possible and
# auditable. Safety properties, all enforced:
#   * refuses to run without an explicit fingerprint list (PRUNE_FPS)
#   * never removes a fingerprint that appears in $SSHKEYS (config.sh is the
#     allowlist -- a typo cannot delete a key the fleet still needs)
#   * dry-run by default: changes nothing unless PRUNE_APPLY=1
#   * writes a dated 0600 backup before touching the file
#   * reports every removal as fingerprint + comment, never as key material
#   * leaves lines it cannot fingerprint alone and says so (see UNPARSEABLE)
#
# Enabling a real run takes two deliberate edits, which is the point:
#   1. add PRUNE_FPS PRUNE_APPLY to the allowlist loop in bin/rexec.sh
#      (rexec exports only whitelisted variables, so until then this payload
#      always sees an empty PRUNE_FPS and exits 1)
#   2. set PRUNE_FPS="<sha256> ..." and PRUNE_APPLY=1 in config.sh
#
# A line carrying an sshd option prefix (restrictions before the key type) is
# matched by its fingerprint too -- ssh-keygen parses those.
set -euo pipefail

die() {
    echo "prune-keys.bash: $*" >&2
    exit 1
}

# --- an explicit list is mandatory --------------------------------------------
if [[ -z "${PRUNE_FPS:-}" ]]; then
    die "refusing to run: PRUNE_FPS is empty. Pass the SHA256:... fingerprints to revoke."
fi

auth_file="$HOME/.ssh/authorized_keys"
[[ -f "$auth_file" ]] || die "no authorized_keys at $auth_file"

fingerprint_of() {
    ssh-keygen -lf - 2>/dev/null | awk '{print $2}'
}

# --- protected set = every key config.sh says the fleet should have -----------
declare -A PROTECTED=()
while IFS= read -r line; do
    [[ -z "${line//[$' \t\r']/}" ]] && continue
    fp="$(printf '%s\n' "$line" | fingerprint_of)"
    [[ -n "$fp" ]] && PROTECTED["$fp"]=1
done <<< "${SSHKEYS:-}"

declare -A WANT=()
readable=0
for tok in $PRUNE_FPS; do
    [[ "$tok" == SHA256:* ]] || die "not a fingerprint: '$tok' (expected SHA256:...)"
    if [[ -n "${PROTECTED[$tok]:-}" ]]; then
        die "refusing: $tok is present in SSHKEYS (config.sh). Remove it from config.sh first if that is really intended."
    fi
    WANT["$tok"]=1
    readable=$((readable + 1))
done
[[ "$readable" -gt 0 ]] || die "PRUNE_FPS held no valid fingerprints"

# --- classify every line before deciding anything -----------------------------
removed=0
kept=0
unparseable=0
kept_unparseable=""
tmp="$(mktemp "${auth_file}.pruning.XXXXXX")"

while IFS= read -r line; do
    if [[ -z "${line//[$' \t\r']/}" ]]; then
        printf '%s\n' "$line" >> "$tmp"
        kept=$((kept + 1))
        continue
    fi
    fp="$(printf '%s\n' "$line" | fingerprint_of || true)"
    if [[ -z "$fp" ]]; then
        # Cannot be fingerprinted, so it cannot be matched safely: keep it and
        # say so. Junk/placeholder lines need a human, not a pattern match.
        unparseable=$((unparseable + 1))
        kept_unparseable+="    $(printf '%s' "$line" | awk '{print $1, "comment="$NF}')"
        printf '%s\n' "$line" >> "$tmp"
        kept=$((kept + 1))
        continue
    fi
    if [[ -n "${WANT[$fp]:-}" ]]; then
        printf 'REMOVE %s  %s\n' "$fp" "$(printf '%s\n' "$line" | ssh-keygen -lf - | awk '{print $3" "$4" "$5}')"
        removed=$((removed + 1))
    else
        printf '%s\n' "$line" >> "$tmp"
        kept=$((kept + 1))
    fi
done < "$auth_file"

# --- report, and only then decide whether to write ----------------------------
echo "prune-keys.bash: matched=$removed kept=$kept unparseable=$unparseable"
if [[ "$unparseable" -gt 0 ]]; then
    printf 'prune-keys.bash: %s unparseable line(s) left in place (no fingerprint to match):\n%s\n' \
        "$unparseable" "$kept_unparseable"
fi

if [[ "${PRUNE_APPLY:-0}" != "1" ]]; then
    rm -f "$tmp"
    echo "prune-keys.bash: DRY RUN -- nothing changed. Re-run with PRUNE_APPLY=1 to apply."
    exit 0
fi

if [[ "$removed" -eq 0 ]]; then
    rm -f "$tmp"
    echo "prune-keys.bash: nothing matched; file left untouched"
    exit 0
fi

ts="$(date +%Y%m%d-%H%M%S)"
backup="$auth_file.bak-prune-$ts"
cp -p -- "$auth_file" "$backup" || die "backup failed, aborting with nothing changed"
chmod 600 -- "$backup" || die "backup chmod failed"

# Refuse to write an empty result: a bug must not be able to lock the operator out.
if [[ ! -s "$tmp" ]] || ! grep -q 'ssh-' "$tmp"; then
    rm -f "$tmp"
    die "refusing to install a result with no key lines (would lock out $HOME); backup at $backup"
fi

mv -- "$tmp" "$auth_file"
chmod 600 -- "$auth_file"
echo "prune-keys.bash: removed $removed key(s); backup at $backup ($ts)"
