#!/usr/bin/env bash
# rofi power menu — green themed
options=" Lock\n Logout\n Suspend\n Reboot\n Shutdown"
chosen=$(echo -e "$options" | rofi -dmenu -i -p "Power" \
    -theme __HOME__/.config/rofi/powermenu.rasi)

# lock/logout differ per compositor; the rest is systemd either way
if [ -n "${SWAYSOCK:-}" ]; then
    lock_cmd="$HOME/.config/sway/lock.sh"; logout_cmd="swaymsg exit"
else
    lock_cmd="hyprlock";                   logout_cmd="hyprctl dispatch exit"
fi

case "$chosen" in
    *Lock)     $lock_cmd ;;
    *Logout)   $logout_cmd ;;
    *Suspend)  systemctl suspend ;;
    *Reboot)   systemctl reboot ;;
    *Shutdown) systemctl poweroff ;;
esac
