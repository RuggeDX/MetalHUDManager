#!/bin/bash
# Fast development loop: compiles a debug build, runs it, and rebuilds and
# relaunches it whenever a source file is saved. Press Ctrl+C to stop.
#
# Usage:
#   scripts/dev.sh          -> build, run, and relaunch on every save
#   scripts/dev.sh --once   -> build and run once
#   MHM_MOCK_UPDATE=1 scripts/dev.sh   -> pretend a new release (v9.9.9) is available
#
# This runs the bare binary rather than the .app bundle, so it has no icon and
# keeps its own settings (e.g. apps added with "Add App…") under the domain
# "MetalHUDManager". Use scripts/build-app.sh for the real app.

set -uo pipefail
cd "$(dirname "$0")/.."

BIN="build/dev/MetalHUDManager"
PID=""

mkdir -p build/dev

stop() {
    if [[ -n "$PID" ]]; then
        kill "$PID" 2>/dev/null
        wait "$PID" 2>/dev/null
    fi
    PID=""
}
trap 'stop; exit 0' INT TERM

build_and_run() {
    echo "==> Compiling ($(date +%H:%M:%S))"
    local sources=()
    for f in Sources/*.swift Sources/*/*.swift; do [[ -f "$f" ]] && sources+=("$f"); done
    if swiftc -parse-as-library -Onone -g -D DEV "${sources[@]}" -o "$BIN.new"; then
        stop
        mv "$BIN.new" "$BIN"
        "$BIN" &
        PID=$!
        echo "==> Running (pid $PID)"
    else
        echo "==> Build failed, keeping the previous version running"
    fi
}

build_and_run

if [[ "${1:-}" == "--once" ]]; then
    [[ -n "$PID" ]] && wait "$PID"
    exit
fi

# Fingerprint of every source file's path and mtime, so edits, new files and
# deletions all trigger a rebuild.
fingerprint() { find Sources -name '*.swift' -exec stat -f '%m %N' {} + | sort | md5; }

echo "==> Watching Sources/ for changes (Ctrl+C to stop)"
last=$(fingerprint)
while true; do
    sleep 1
    now=$(fingerprint)
    if [[ "$now" != "$last" ]]; then
        last=$now
        build_and_run
    fi
done
