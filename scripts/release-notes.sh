#!/bin/bash
# Prints the CHANGELOG.md section for a version, used as its GitHub release notes.
#
# Usage: scripts/release-notes.sh 1.1.0

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: scripts/release-notes.sh <version>}"

NOTES="$(awk -v v="$VERSION" '
    /^## \[/ { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
    /^\[[^]]+\]: / { next }
    found { print }
' CHANGELOG.md | sed -e '/./,$!d')"

if [[ -z "${NOTES//[[:space:]]/}" ]]; then
    NOTES="See [CHANGELOG.md](https://github.com/RuggeDX/MetalHUDManager/blob/main/CHANGELOG.md)."
fi
printf '%s\n' "$NOTES"
