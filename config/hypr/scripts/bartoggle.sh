#!/usr/bin/env bash
# Toggle between the PROTO//GREEN quickshell visor bar and the waybar fallback.
# Idempotent: ALWAYS ends with exactly one bar, even if state drifted to
# both-running or none-running (the old cause of "double bars").
set -uo pipefail

# pick the target: if the visor is up, go to waybar; otherwise go to visor
if pgrep -x qs >/dev/null 2>&1; then
    target=waybar
else
    target=qs
fi

# tear down BOTH bars unconditionally (kills any stragglers/duplicates)
pkill -x qs       2>/dev/null || true
pkill -x waybar   2>/dev/null || true
sleep 0.3

if [ "$target" = waybar ]; then
    waybar >/dev/null 2>&1 &
    notify-send "PROTO//GREEN" "switched to waybar fallback" -t 2000 || true
else
    qs -c protogreen >/dev/null 2>&1 &
    notify-send "PROTO//GREEN" "visor bar online ◕▿◕" -t 2000 || true
fi
