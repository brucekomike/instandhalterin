#!/bin/bash
#
# configstrap.sh — create config.sh from config.sh.example when it is missing.
#
# Usage: bin/configstrap.sh
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$here/config.sh.example"
dst="$here/config.sh"

if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    echo "Created $dst from config.sh.example"
else
    echo "$dst already exists; leaving it unchanged"
fi
