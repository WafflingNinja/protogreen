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

# ------------------------------------------------------------------ disclaimer
r "READ THIS FIRST"
cat <<'EOF'
  This is my personal desktop config, published as-is under the MIT licence.
  It is NOT a product and it comes with NO WARRANTY OF ANY KIND.

  It was built for ONE machine: an Arch/CachyOS laptop with an Intel iGPU, an
  NVIDIA dGPU and a single 1080p144 internal panel. This installer adapts the
  GPU and monitor parts for your hardware, but it cannot test your hardware.

  What this script does to your system:
    - installs packages with pacman (and optionally from the AUR)
    - RENAMES existing directories in ~/.config to <name>.bak-<date>
      (it never overwrites in place, and it asks before each step)
    - optionally installs ollama and downloads a ~2 GB model

  If something breaks - your configs, your session, your packages, your data -
  that is on you, not on me. Back up anything you care about BEFORE continuing.
  If you are not comfortable with that, press Ctrl-C now and read the configs
  in config/ by hand instead; they are plain text and copying them yourself is
  a perfectly good way to use this repo.
EOF
echo
read -rp "  Type 'yes' to accept and continue: " AGREE
[ "$AGREE" = "yes" ] || { y "  Not accepted. Nothing was changed."; exit 0; }
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
CONFIGS_DONE=0
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
  CONFIGS_DONE=1
  g "  configs installed"
fi

# ------------------------------------------------------------------ hardware
HYPRCONF="$DEST/hypr/hyprland.conf"

# Replace the marked block in hyprland.conf with $2, keeping the markers.
# $1 = marker word (GPU PROFILE / MONITOR), $2 = replacement body.
replace_block() {
  local marker="$1" body="$2"
  [ -f "$HYPRCONF" ] || return 1
  # An older install (or a hand-edited file) has no markers. Say so rather than
  # running awk over it and reporting a success that did nothing.
  grep -q ">>> PROTOGREEN $marker >>>" "$HYPRCONF" || {
    y "  no '$marker' marker in $HYPRCONF — skipping (file predates this installer,"
    y "  or was edited by hand). Nothing changed."
    return 1
  }
  awk -v m="$marker" -v body="$body" '
    $0 ~ ">>> PROTOGREEN " m " >>>" { print; print body; skip=1; next }
    $0 ~ "<<< PROTOGREEN " m " <<<" { skip=0 }
    !skip
  ' "$HYPRCONF" > "$HYPRCONF.tmp" && mv "$HYPRCONF.tmp" "$HYPRCONF"
}

# Steps 5 and 6 edit an EXISTING ~/.config. If step 4 was skipped, that file is
# the user's own, not one we just wrote — ask before touching it.
hw_ok() {
  [ -f "$HYPRCONF" ] || { y "  no $HYPRCONF — install the configs first (step 4)"; return 1; }
  [ "$CONFIGS_DONE" = 1 ] && return 0
  y "  configs were NOT installed this run, so this would edit your existing"
  y "  $HYPRCONF in place."
  ask "  edit it anyway?" || { y "  skipped"; return 1; }
}

y "[5] GPU profile"
if ! hw_ok; then
  :
else
  GPU=intel
  GPUNAME="Intel (or unknown)"
  if lspci 2>/dev/null | grep -qi 'vga\|3d\|display'; then
    if lspci 2>/dev/null | grep -i 'vga\|3d' | grep -qi nvidia; then
      GPU=nvidia; GPUNAME="$(lspci | grep -i 'vga\|3d' | grep -i nvidia | head -1 | cut -d: -f3- | sed 's/^ *//')"
    elif lspci 2>/dev/null | grep -i 'vga\|3d' | grep -qi 'amd\|ati\|radeon'; then
      GPU=amd;    GPUNAME="$(lspci | grep -i 'vga\|3d' | grep -Ei 'amd|ati|radeon' | head -1 | cut -d: -f3- | sed 's/^ *//')"
    else
      GPUNAME="$(lspci | grep -i 'vga\|3d' | head -1 | cut -d: -f3- | sed 's/^ *//')"
    fi
  fi

  describe_gpu() {
    case "$1" in
      nvidia) echo "  - keep NVIDIA env block (GLX on the dGPU, VA-API pinned to the iGPU)";;
      amd)    echo "  - drop the NVIDIA env block; mesa picks the VA driver on its own";;
      intel)  echo "  - drop the NVIDIA env block; VA-API pinned to iHD";;
    esac
    echo "  - GPU readout is vendor-agnostic already (scripts/gpu-read.sh)"
  }

  echo "  detected: $GPUNAME  ->  profile '$GPU'"
  describe_gpu "$GPU"
  if ! ask "  use this profile?"; then
    echo "  1) nvidia-hybrid   2) amd   3) intel"
    read -rp "  choice [1-3]: " c
    case "$c" in 1) GPU=nvidia;; 2) GPU=amd;; 3) GPU=intel;; *) y "  unrecognised — keeping '$GPU'";; esac
  fi

  case "$GPU" in
    nvidia) BODY='# nvidia-hybrid: Intel panel + NVIDIA dGPU.
# LIBVA=iHD — the panel is Intel-driven, so video DECODE belongs on the iGPU.
env = LIBVA_DRIVER_NAME,iHD
env = PROTOGREEN_VAAPI,iHD
# GLX stays nvidia: Xwayland games want the dGPU.
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct' ;;
    amd)    BODY='# amd: nothing to pin. mesa picks the right VA driver by itself, and the
# NVIDIA vars above would only send GLX somewhere that does not exist.' ;;
    intel)  BODY='# intel only: panel and decode are both on the iGPU.
env = LIBVA_DRIVER_NAME,iHD
env = PROTOGREEN_VAAPI,iHD' ;;
  esac
  replace_block "GPU PROFILE" "$BODY" && g "  applied '$GPU' profile to hyprland.conf"
fi

y "[6] monitor"
if ! hw_ok; then
  :
else
  # Read the connected output and its first (preferred) mode straight from DRM,
  # so this works from a TTY with no compositor running.
  OUT=""; MODE=""
  for card in /sys/class/drm/card*-*; do
    [ -r "$card/status" ] || continue
    [ "$(< "$card/status")" = "connected" ] || continue
    [ -r "$card/modes" ] || continue
    MODE="$(head -1 "$card/modes")"
    [ -n "$MODE" ] || continue          # connected but no modes = not usable
    OUT="${card##*/card?-}"             # /sys/class/drm/card1-eDP-1 -> eDP-1
    break
  done

  if [ -n "$OUT" ] && [ -n "$MODE" ]; then
    echo "  detected: $OUT @ $MODE"
    y "  note: refresh rate is not in sysfs — the line below omits it, so Hyprland"
    y "        picks the highest available. Add @<hz> yourself to pin one."
    if ask "  replace the hard-coded eDP-1 line with this?"; then
      replace_block "MONITOR" "monitor = $OUT,$MODE,0x0,1" \
        && g "  monitor line set to: $OUT,$MODE,0x0,1"
    else
      y "  left as-is — edit $HYPRCONF if the display comes up wrong"
    fi
  else
    y "  could not detect a connected output"
    y "  the hard-coded eDP-1 line stays; if your panel differs, edit $HYPRCONF"
    y "  (deleting that line is fine — the ',preferred,auto,1' fallback takes over)"
  fi
fi

# ------------------------------------------------------------------ wallpaper
y "[7] wallpaper"
echo "  Static:   ~/.config/hypr/wallpapers/green-furry.png (hyprpaper)"
echo "  Animated: ~/.config/hypr/wallpapers/protogen-neon.mp4 (mpvpaper, via scripts/power-watch.sh)"
echo "  The animated one is a conversion of Wallpaper Engine workshop item 3157997169"
echo "  (art by its original creator — swap it for your own if you prefer)."

# ------------------------------------------------------------------ session
y "[8] session"
echo "  Log out and pick 'Hyprland' at your display manager."
echo "  Keybinds: SUPER=launcher · SUPER+Q=kitty · SUPER+E=files · SUPER+C=close"
echo "            SUPER+SHIFT+B=switch visor bar <-> waybar · SUPER+SHIFT+S=screenshot"
g "Done."
