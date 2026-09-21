#!/usr/bin/env bash
# PROTO//GREEN installer — Arch / CachyOS.
#
# Copies the configs in this repo into ~/.config, backing up anything that is
# already there. Every step asks first. Nothing is overwritten silently.
#
#   bash install.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO/config"
DEST="$HOME/.config"
STAMP="$(date +%Y%m%d-%H%M%S)"
PLACEHOLDER="__HOME__"          # stands in for your home dir inside the shipped configs

g(){ printf '\033[1;32m%s\033[0m\n' "$*"; }
y(){ printf '\033[33m%s\033[0m\n' "$*"; }
r(){ printf '\033[31m%s\033[0m\n' "$*"; }
ask(){ read -rp "$1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

command -v pacman >/dev/null || { r "Not an Arch-based system (no pacman). Stopping."; exit 1; }
[ -d "$SRC" ] || { r "config/ not found next to this script. Run it from the repo."; exit 1; }

g "== PROTO//GREEN setup =="
echo "repo:   $REPO"
echo "target: $DEST"
echo

# ------------------------------------------------------------------ packages
PKGS=(
  hyprland hypridle hyprlock hyprpaper hyprpicker hyprsunset
  xdg-desktop-portal-hyprland
  quickshell waybar rofi rofi-emoji dunst kitty thunar
  cava btop fastfetch mpvpaper
  cliphist wl-clipboard grim slurp satty
  playerctl pamixer brightnessctl power-profiles-daemon polkit-gnome
  qt6ct imagemagick jq socat python-pillow python-evdev python-pyqt6
  papirus-icon-theme papirus-folders adw-gtk-theme ttf-jetbrains-mono-nerd
)

y "[1] packages (${#PKGS[@]})"
echo "  ${PKGS[*]}"
if ask "  install with pacman?"; then
  sudo pacman -S --needed "${PKGS[@]}" || y "  some packages failed — check output above"
fi

HELPER=""
command -v paru >/dev/null && HELPER=paru
[ -z "$HELPER" ] && command -v yay >/dev/null && HELPER=yay
y "[2] animated wallpaper (optional, AUR)"
echo "  linux-wallpaperengine-git — plays Wallpaper Engine workshop items."
echo "  Skip it and the static PNG wallpaper is used instead."
if [ -n "$HELPER" ]; then
  ask "  install linux-wallpaperengine-git with $HELPER?" && "$HELPER" -S --needed linux-wallpaperengine-git
else
  y "  no paru/yay found — skipping"
fi

y "[3] Pip assistant — OPTIONAL, say no if unsure"
echo "  Only the CHAT half needs a model. The desktop commands in the SUPER+A popup"
echo "  (open apps, workspaces, volume, brightness, screenshots, lock) are plain code"
echo "  and work with nothing installed. Skipping this changes nothing else."
echo "  Cost if you do want chat: ~2 GB download, ~4 GB RAM while answering,"
echo "  usable on CPU, faster with a GPU."
if ask "  install ollama and pull llama3.2:3b?"; then
  sudo pacman -S --needed ollama && sudo systemctl enable --now ollama && ollama pull llama3.2:3b
fi

# ------------------------------------------------------------------ configs
y "[4] configs"
mapfile -t DIRS < <(cd "$SRC" && ls -1)
echo "  will install: ${DIRS[*]}"
echo "  existing dirs get renamed to <name>.bak-$STAMP"
if ask "  copy configs into $DEST?"; then
  mkdir -p "$DEST"
  for d in "${DIRS[@]}"; do
    if [ -e "$DEST/$d" ]; then
      mv "$DEST/$d" "$DEST/$d.bak-$STAMP"
      echo "  backed up $d -> $d.bak-$STAMP"
    fi
    cp -a "$SRC/$d" "$DEST/$d"
  done

  # Some configs (dunst, qt6ct, hyprpaper, QML) take absolute paths and expand
  # neither ~ nor $HOME, so they ship with __HOME__ and get it filled in here.
  grep -rlI "$PLACEHOLDER" "${DIRS[@]/#/$DEST/}" 2>/dev/null \
    | xargs -r sed -i "s|$PLACEHOLDER|$HOME|g"
  echo "  filled in $PLACEHOLDER -> $HOME"

  chmod +x "$DEST"/hypr/scripts/* 2>/dev/null
  chmod +x "$DEST"/quickshell/protogreen/services/*.sh 2>/dev/null
  g "  configs installed"
fi

# ------------------------------------------------------------------ wallpaper
y "[5] wallpaper"
echo "  Static:   ~/.config/hypr/wallpapers/green-furry.png (hyprpaper)"
echo "  Animated: ~/.config/hypr/wallpapers/protogen-neon.mp4 (mpvpaper, via scripts/power-watch.sh)"
echo "  The animated one is a conversion of Wallpaper Engine workshop item 3157997169"
echo "  (art by its original creator — swap it for your own if you prefer)."

# ------------------------------------------------------------------ session
y "[6] session"
echo "  Log out and pick 'Hyprland' at your display manager."
echo "  Keybinds: SUPER=launcher · SUPER+Q=kitty · SUPER+E=files · SUPER+C=close"
echo "            SUPER+SHIFT+B=switch visor bar <-> waybar · SUPER+SHIFT+S=screenshot"
g "Done."
