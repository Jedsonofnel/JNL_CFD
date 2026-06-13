#!/usr/bin/env bash

set -euo pipefail

CLI="bin/debug/cli"
SCRIPT="web/main.lua"

export JNL_DEV=1

trap 'kill "${PID:-}" 2>/dev/null; wait "${PID:-}" 2>/dev/null || true' EXIT INT TERM

if command -v entr >/dev/null 2>&1; then
    find lua/flux web -name "*.lua" | entr -r "$CLI" "$SCRIPT"
else
    echo "watch_docs: entr not found, falling back to polling" >&2
    MARKER=$(mktemp)
    "$CLI" "$SCRIPT" & PID=$!
    while sleep 0.5; do
        if find lua/flux web -name "*.lua" -newer "$MARKER" | grep -q .; then
            touch "$MARKER"
            echo "flux: change detected, restarting..."
            kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null || true
            "$CLI" "$SCRIPT" & PID=$!
        fi
    done
fi
