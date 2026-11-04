#!/bin/bash
# Fast development loop: compiles a debug build, runs it, and rebuilds and
# relaunches it whenever the source file is saved. Press Ctrl+C to stop.
#
# Usage:
#   ./dev.sh          -> build, run, and relaunch on every save
#   ./dev.sh --once   -> build and run once
#   MHM_MOCK_UPDATE=1 ./dev.sh   -> pretend a new release (v9.9.9) is available
#
# This runs the bare binary rather than the .app bundle, so it has no icon and
# keeps its own settings (e.g. apps added with "Add App…") under the domain
# "MetalHUDManager". Use ./build-app.sh for the real app.

set -uo pipefail
cd "$(dirname "$0")"

SOURCE="Sources/MetalHUDManager.swift"
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
    if swiftc -parse-as-library -Onone -g -D DEV "$SOURCE" -o "$BIN.new"; then
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

echo "==> Watching $SOURCE for changes (Ctrl+C to stop)"
last=$(stat -f %m "$SOURCE")
while true; do
    sleep 1
    now=$(stat -f %m "$SOURCE")
    if [[ "$now" != "$last" ]]; then
        last=$now
        build_and_run
    fi
done
