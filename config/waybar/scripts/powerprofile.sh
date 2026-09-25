#!/usr/bin/env bash
# Power-profile selector for waybar.  Single source of truth = powerprofilesctl,
# so the button can never show a stale/"mixed" state — it always reads the live
# active profile back.
#
#   left-click   cycle  performance -> balanced -> power-saver  (+ MANUAL override)
#   right-click  auto    clear override, apply the power-source default
#
# The MANUAL override file tells power-watch.sh to STOP auto-switching the profile
# (it otherwise forces balanced on AC / power-saver on battery and would silently
# wipe a manual pick — the "mixed options" bug). While overridden, power-watch
# still manages the wallpaper, just not the profile.
set -uo pipefail

MANUAL=/tmp/power-profile.manual
BAT="$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)/status"

cur()         { powerprofilesctl get 2>/dev/null; }
on_battery()  { [ "$(cat "$BAT" 2>/dev/null)" = "Discharging" ]; }
refresh()     { pkill -RTMIN+8 waybar 2>/dev/null || true; }   # repaint the module now

# glyphs printed at runtime (Nerd Font, FontAwesome BMP) so the source stays ASCII
icon() {
    case "$1" in
        performance) printf '' ;;   # bolt
        balanced)    printf '' ;;   # balance-scale
        power-saver) printf '' ;;   # leaf
        *)           printf '' ;;   # question-circle (unknown)
    esac
}

case "${1:-status}" in
    status)
        p=$(cur)
        if [ -z "$p" ]; then
            printf '{"text":"%s","class":"unknown","tooltip":"power-profiles-daemon not responding"}\n' "$(icon x)"
            exit 0
        fi
        mode="auto"; [ -f "$MANUAL" ] && mode="manual"
        printf '{"text":"%s","class":"%s","tooltip":"Power profile: %s  (%s)\\nleft-click: cycle   right-click: auto"}\n' \
            "$(icon "$p")" "$p" "$p" "$mode"
        ;;
    cycle)
        case "$(cur)" in
            performance) n=balanced    ;;
            balanced)    n=power-saver ;;
            power-saver) n=performance ;;
            *)           n=balanced    ;;
        esac
        if powerprofilesctl set "$n" 2>/dev/null; then echo "$n" > "$MANUAL"; fi
        refresh
        ;;
    set)
        n="${2:-balanced}"
        if powerprofilesctl set "$n" 2>/dev/null; then echo "$n" > "$MANUAL"; fi
        refresh
        ;;
    auto)
        rm -f "$MANUAL"
        if on_battery; then powerprofilesctl set power-saver 2>/dev/null || true
        else                powerprofilesctl set balanced   2>/dev/null || true
        fi
        refresh
        ;;
esac
