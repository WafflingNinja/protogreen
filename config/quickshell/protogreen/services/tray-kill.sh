#!/usr/bin/env bash
# Terminate a system-tray (SNI) app by its reported Id.
# Usage: tray-kill.sh <sni-id> [--print]
#   --print  resolve and echo the PID, do not kill (for testing)
# Maps the tray item's StatusNotifierItem Id to the owning process via DBus,
# then sends SIGTERM. Quickshell's SystemTrayItem exposes .id but not the PID,
# so we resolve it here at click time.
set -euo pipefail

target="${1:-}"
[[ -z "$target" ]] && { echo "no id given" >&2; exit 2; }

watcher=org.kde.StatusNotifierWatcher
items=$(busctl --user get-property "$watcher" /StatusNotifierWatcher \
            "$watcher" RegisteredStatusNotifierItems \
        | sed -E 's/^as[0-9 ]*//; s/"//g')

for item in $items; do
    bus="${item%%/*}"          # e.g. ":1.104"
    path="/${item#*/}"         # e.g. "/StatusNotifierItem"
    id=$(busctl --user get-property "$bus" "$path" \
             org.kde.StatusNotifierItem Id 2>/dev/null \
         | sed -E 's/^s "//; s/"$//') || continue
    [[ "$id" == "$target" ]] || continue

    pid=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
              org.freedesktop.DBus GetConnectionUnixProcessID s "$bus" \
          | awk '{print $2}')
    [[ -z "$pid" ]] && { echo "no pid for $bus" >&2; exit 1; }

    if [[ "${2:-}" == "--print" ]]; then
        echo "$pid"
    else
        kill "$pid"
    fi
    exit 0
done

echo "no tray item with id '$target'" >&2
exit 1
