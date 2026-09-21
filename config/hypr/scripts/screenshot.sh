#!/usr/bin/env bash
# screenshot: region | window | full  → annotate in satty (auto-copies)
mode="${1:-region}"
dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
out="$dir/$(date +%Y%m%d-%H%M%S).png"

case "$mode" in
    region) grim -g "$(slurp)" - ;;
    # focused-window geometry: sway (i3 IPC) or Hyprland, whichever session this is
    window)
        if [ -n "${SWAYSOCK:-}" ]; then
            geom=$(swaymsg -t get_tree | jq -r 'recurse(.nodes[]?,.floating_nodes[]?) | select(.focused) | "\(.rect.x),\(.rect.y) \(.rect.width)x\(.rect.height)"')
        else
            geom=$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
        fi
        grim -g "$geom" - ;;
    full)   grim - ;;
esac | satty --filename - --output-filename "$out" --early-exit --copy-command 'wl-copy' --init-tool brush
