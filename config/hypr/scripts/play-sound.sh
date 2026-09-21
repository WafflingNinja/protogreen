#!/bin/bash
# play-sound.sh <name> [debounce_ms] — plays random variant from ~/.config/hypr/sounds/pool/<name>/
pool="$HOME/.config/hypr/sounds/pool/$1"
mapfile -t variants < <(find "$pool" -name '*.ogg' 2>/dev/null)
[ "${#variants[@]}" -gt 0 ] || exit 0
snd="${variants[RANDOM % ${#variants[@]}]}"

debounce_ms="${2:-0}"
if [ "$debounce_ms" -gt 0 ]; then
    stamp="/tmp/hypr-sound-$1.stamp"
    now=$(date +%s%3N)
    last=$(cat "$stamp" 2>/dev/null || echo 0)
    if [ $((now - last)) -lt "$debounce_ms" ]; then
        exit 0
    fi
    echo "$now" > "$stamp"
fi

pw-play "$snd" &
