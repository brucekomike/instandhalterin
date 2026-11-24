#!/bin/bash
#
# no-host-identifiers_test.sh — the pre-push gate for site data.
#
# Why this exists instead of a rule in a README: on 2026-11-24 a worker verified
# `git remote get-url origin`, saw a plausible URL, and committed a design doc plus
# the real per-host lists into this repository WITHOUT checking that it is PUBLIC.
# The repo's own rhosts/.gitignore already said "may contain sensitive hostnames";
# that committed policy was overridden on a coordinator's assertion, and production
# NAT entry addresses, cloud instance ids and a service topology went public. A
# guardrail that depends on judgement failed the same day it was noted. This runs
# automatically.
#
# Usage:
#   bash ubuntu/tests/no-host-identifiers_test.sh               # tracked tree
#   bash ubuntu/tests/no-host-identifiers_test.sh --range A..B  # also scan a range
#
# Design: generic SHAPE rules live here. Site-specific literals live in
# ubuntu/tests/host-identifiers.local, which is gitignored -- hardcoding this
# fleet's alias prefixes into a public repo would itself be the leak this gate is
# meant to catch. Locally, that file is what makes the gate fleet-aware.
#
# Design note, stated because it WILL surprise someone: this rule is deliberately
# fail-closed, so a version string that happens to read as four dotted numbers
# (a product name followed by 9.9.9.x) is reported too -- this very file tripped
# it while describing it. That is the accepted cost: heuristics that suppress it
# (require a 3-digit octet, require an IP-looking neighbour) are exactly what lets
# a real entry address through, and a missed EIP is the failure this gate exists to
# prevent. When it trips, reword the line to a masked form, do not loosen the rule.
#
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$root/.." && pwd)"
range=""
if [[ "${1:-}" == "--range" ]]; then
    range="${2:?--range needs a rev range like main..HEAD}"
fi

violations=0
report() {
    printf 'HOST-IDENTIFIER %s\n' "$1" >&2
    violations=$((violations + 1))
}

# RFC1918 is the only "private" space that can identify a real machine on a site's
# own network. TEST-NET documentation ranges are NOT site data.
NON_SITE='^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'
# Never site data in any file, template or not: loopback, unspecified, broadcast,
# multicast, and the three TEST-NET documentation ranges.
ALWAYS_OK='^(127\.|0\.0\.0\.0|255\.255\.255\.255|22[4-9]\.|23[0-9]\.|24[0-9]\.|25[0-5]\.|192\.0\.2\.|198\.51\.100\.|203\.0\.113\.)'

# Files whose whole purpose is to show shape with synthetic values.
is_template() {
    case "$(basename "$1")" in
        *.example|*_test.sh) return 0 ;;
        *) return 1 ;;
    esac
}

# --- the file set -------------------------------------------------------------
files="$(cd "$repo" && git ls-files)"
if [[ -n "$range" ]]; then
    # a push can leak a blob that the final tree no longer shows, so scan the
    # whole range's added/deleted names too, not just HEAD
    more="$(cd "$repo" && git diff --name-only "$range" 2>/dev/null || true)"
    files="$(printf '%s\n%s\n' "$files" "$more" | sed '/^$/d' | sort -u)"
fi

for f in $files; do
    [[ "$f" == "ubuntu/tests/host-identifiers.local" ]] && continue
    [[ -f "$repo/$f" ]] || continue

    # NOTE: never write `grep -q X && continue` here -- when X is absent (the
    # common case) the AND-list returns 1 and set -e aborts the whole gate
    # before it can report anything. Use an explicit if.
    while read -r ip; do
        [[ -n "$ip" ]] || continue
        if printf '%s' "$ip" | grep -qE "$ALWAYS_OK"; then
            continue
        fi
        if printf '%s' "$ip" | grep -qE "$NON_SITE"; then
            # private space is only meaningful in a real file, where it identifies
            # a machine on the site's own network
            if ! is_template "$f"; then
                report "$f: host address '$ip' in a non-template file"
            fi
        else
            report "$f: publicly routable IPv4 '$ip'"
        fi
    done < <(grep -ohE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$repo/$f" 2>/dev/null | sort -u)

    # instance identifiers name one machine rather than a role
    while read -r id; do
        [[ -n "$id" ]] || continue
        report "$f: instance identifier '$id'"
    done < <(grep -ohE '\b(ecs|bms)-[a-z0-9][a-z0-9-]{2,}\b' "$repo/$f" 2>/dev/null | sort -u)

    # NOTE: `grep -q X && report` would abort under set -e on the COMMON case
    # (no match), so the absence of a private key is tested with an if.
    if grep -qE -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$repo/$f" 2>/dev/null; then
        report "$f: private key material"
    fi
done

# --- structural invariant: per-host lists stay unversioned -------------------
tracked="$(cd "$repo" && git ls-files -- 'ubuntu/rhosts/*.txt' || true)"
if [[ -n "$tracked" ]]; then
    while read -r f; do
        [[ -n "$f" ]] || continue
        report "$f: a per-host list is TRACKED"
        echo "    rhosts/.gitignore keeps host names out of this public repo." >&2
        echo "    git rm --cached it, commit <group>.example instead." >&2
        echo "    bin/inventory-rgroups.sh refuses to write a tracked path for the same reason." >&2
    done <<<"$tracked"
fi

# --- site-specific literals, from the gitignored extras ----------------------
local_rules="$repo/ubuntu/tests/host-identifiers.local"
if [[ -f "$local_rules" ]]; then
    while IFS= read -r pat; do
        [[ -z "$pat" || "$pat" == \#* ]] && continue
        hits="$(cd "$repo" && grep -rnE -- "$pat" --exclude=host-identifiers.local $(git ls-files) 2>/dev/null | head -20 || true)"
        [[ -n "$hits" ]] || continue
        while IFS= read -r h; do
            report "site pattern '$pat' at ${h%%:*}"
            echo "    ${h#*:}" >&2
        done <<<"$hits"
    done < <(grep -vE '^[[:space:]]*$' "$local_rules")
fi

if [[ "$violations" -gt 0 ]]; then
    echo >&2
    echo "no-host-identifiers_test.sh: FAILED -- $violations finding(s)." >&2
    echo "  This repo is PUBLIC: it ships the shape of the fleet, never the fleet." >&2
    echo "  Site facts belong in the private docs of record." >&2
    exit 1
fi

echo "no-host-identifiers_test.sh: clean ($(printf '%s\n' "$files" | sed '/^$/d' | wc -l) blobs scanned)"
