#!/bin/bash
# Runs the same checks as the Lint workflow on GitHub: SwiftLint on Sources/
# and ShellCheck on scripts/.
#
# Usage:
#   scripts/lint.sh         -> report problems
#   scripts/lint.sh --fix   -> let SwiftLint fix what it can, then report the rest
#
# Install the tools with: brew install swiftlint shellcheck

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

for tool in swiftlint shellcheck; do
    command -v "$tool" >/dev/null || { echo "$tool not found. Run: brew install swiftlint shellcheck"; exit 1; }
done

status=0

if [[ "${1:-}" == "--fix" ]]; then
    echo "==> SwiftLint (fix)"
    swiftlint --fix --quiet
fi

echo "==> SwiftLint"
swiftlint lint --strict --quiet || status=1

echo "==> ShellCheck"
shellcheck --format=gcc scripts/*.sh || status=1

if [[ $status -eq 0 ]]; then echo "All checks passed."; fi
exit $status
