#!/bin/bash
#
# configstrap.sh — create config.sh from config.sh.example when it is missing.
#
# Usage: bin/configstrap.sh
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cfg="${IH_CONFIG:-$here/../../.config/ihconfig}"
[[ -d "$cfg" ]] || cfg="$here"
src="$here/config.sh.example"
dst="$cfg/config.sh"

if [[ ! -f "$dst" ]]; then
    mkdir -p "$cfg"
    cp "$src" "$dst"
    echo "Created $dst from config.sh.example"
else
    echo "$dst already exists; leaving it unchanged"
fi
