#!/usr/bin/env bash
# now-playing for waybar; outputs JSON with play/pause class. empty when stopped.
status=$(playerctl status 2>/dev/null)
if [ "$status" != "Playing" ] && [ "$status" != "Paused" ]; then
    echo '{"text":"","tooltip":""}'
    exit 0
fi
title=$(playerctl metadata --format '{{title}} - {{artist}}' 2>/dev/null | cut -c1-45)
# escape quotes for JSON
title=${title//\"/\'}
icon=$(printf '\uf001')
echo "{\"text\":\"$icon  $title\",\"class\":\"$status\",\"tooltip\":\"$status\"}"
