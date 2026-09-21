#!/bin/bash
# hypr-sound-listener.sh — plays sounds on window open/close/workspace switch
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
PLAY="$HOME/.config/hypr/scripts/play-sound.sh"

socat -U - UNIX-CONNECT:"$SOCK" | while read -r line; do
    case "$line" in
        openwindow\>\>*)  "$PLAY" open ;;
        closewindow\>\>*) "$PLAY" close ;;
        workspace\>\>*)   "$PLAY" workspace 150 ;;
    esac
done
