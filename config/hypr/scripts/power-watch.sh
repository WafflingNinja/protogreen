#!/usr/bin/env bash
# Single wallpaper + power authority (runs as the user, no sudo). Polls every 3s
# and applies the desired state only when it changes:
#   game running → no ANIMATED wallpaper, static image instead (frees the iGPU behind
#                  windowed games = kills the rare compositor/wallpaper-GC freeze);
#                  profile left to sober-launch.
#   on battery   → power-saver profile + STATIC wallpaper (saves ~212MB + iGPU render)
#   on AC        → balanced profile + ANIMATED wallpaper
# Launched from hyprland exec-once.
set -uo pipefail

# single instance (lock holder is killable via: fuser -k /tmp/power-watch.lock)
exec 9>"/tmp/power-watch.lock"
flock -n 9 || exit 0

BAT=/sys/class/power_supply/BAT1/status
WP_ID=3157997169
STATIC="$HOME/.config/hypr/wallpapers/green-furry.png"
# Active wallpaper is owned by the theme panel: it writes the chosen mp4 path here
# (one line, no quoting) whenever you pick one from the wallpaper grid. Falls back to
# the original pre-rendered scene if the pointer is missing or points at nothing.
WP_POINTER="$HOME/.config/protogreen/wallpaper.path"
DEFAULT_VIDEO="$HOME/.config/hypr/wallpapers/protogen-neon.mp4"
MON=eDP-1
MANUAL=/tmp/power-profile.manual          # set by waybar powerprofile.sh "cycle"/"set"
WP_FPS=30                                 # animated wallpaper framerate
state=""

# ensure hyprctl/qs can reach the compositor even if launched bare (normally inherited)
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"; export XDG_RUNTIME_DIR
: "${WAYLAND_DISPLAY:=wayland-1}"; export WAYLAND_DISPLAY
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    export HYPRLAND_INSTANCE_SIGNATURE="$(basename "$(dirname "$(find "$XDG_RUNTIME_DIR/hypr" -name .socket.sock 2>/dev/null | head -1)")")"
fi

on_battery()   { [ "$(cat "$BAT" 2>/dev/null)" = "Discharging" ]; }
# Heavy task = pause the animated wallpaper (it's occluded behind a game anyway,
# so frees the iGPU). pgrep -f matches the full cmdline. NOTE: never put a bare
# "proton" here — it substring-matches "protogreen" (the quickshell bar) and the
# wallpaper would never come back; Steam's Proton games match via steam_app_.
GAME_RE='org.vinegarhq.Sober|RobloxPlayer|sober-launch|BeamNG.drive|beamng.sh'   # roblox + beamng
# 'reaper SteamLaunch' = an actual Steam game launch. Do NOT use pressure-vessel /
# SteamLinuxRuntime / steamwebhelper — those run for the Steam CLIENT too, so the
# wallpaper would vanish whenever Steam is merely open.
GAME_RE="$GAME_RE"'|gamescope|reaper SteamLaunch'                                 # steam game launch / gamescope
GAME_RE="$GAME_RE"'|lutris|heroic|bottles-cli|wine64-preloader|wine-preloader'    # non-steam launchers + wine
GAME_RE="$GAME_RE"'|rpcs3|pcsx2|dolphin-emu|yuzu|ryujinx|cemu|ppsspp|duckstation|melonDS|retroarch'  # emulators
GAME_RE="$GAME_RE"'|blender|DaVinciResolve'                                       # heavy GPU creative
_game_probe()  { pgrep -af "$GAME_RE" >/dev/null 2>&1; }
# ponytail: probed once per loop tick, not once per call. game_running is asked 3x a
# tick (apply + both self-heals), which was 3 pgrep+grep pairs every 3s, forever.
game_running() { [ "$_game_cached" = 1 ]; }
# honor a manual profile pick from the waybar button: while it exists, DON'T touch
# the power profile (only the wallpaper). Right-clicking the button clears it.
set_profile()  { [ -f "$MANUAL" ] && return 0; powerprofilesctl set "$1" 2>/dev/null || true; }

# Wallpaper = mpvpaper playing the mp4 loop (~220MB vs qs -c wallpaper's ~549MB).
# mpv DOES crash this hybrid box when it grabs NVIDIA or a GL context — so force the
# Intel iGPU (mesa EGL vendor + iHD vaapi) and a VULKAN wayland context; that combo is
# the only one that survives here (plain gpu-context=wayland/GL dies). Match by cmdline
# (contains "protogen-neon" — never matches this script, so pkill -f is safe).
# LIBVA_DRIVER_NAME is pinned ONLY on the NVIDIA profile. The pin exists to stop
# mpv picking NVIDIA's libva; on an AMD or Intel-only box there is no NVIDIA libva
# to avoid, and mesa picks the right driver by itself. install.sh sets PROTOGREEN_VAAPI.
MPV_ENV=(env __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json)
[ -n "${PROTOGREEN_VAAPI:-}" ] && MPV_ENV+=("LIBVA_DRIVER_NAME=$PROTOGREEN_VAAPI")
# vo stays gpu/waylandvk — MEASURED 2026-08-07, not assumed. vo=dmabuf-wayland was
# tested as the "lighter" option (no GL context, vaapi surface handed straight to the
# compositor) and came out identical: 262MB/20%-of-a-core vs gpu's 270MB/20%, same
# clip, same conditions. hwdec is confirmed active either way ("Using hardware decoding
# (vaapi)"), so that 20% is mpv's present path, not decode — no VO can remove it.
# The only real lever on wallpaper cost is the VIDEO itself (fps/bitrate/resolution),
# which is why those are sliders in the theme panel now. THEME_VO=dmabuf-wayland opts in.
MPV_VO="${THEME_VO:-gpu}"
# Wallpaper audio. The stream is ALWAYS created (muting is done at runtime over the
# IPC socket, so toggling sound in the panel never needs a restart) and carries a
# unique audio-client-name — mpvpaper is mpv, so without it we could not tell our own
# stream apart from any other mpv the user is running when deciding to auto-mute.
WP_SOCK=/tmp/protogreen-wp.sock
WP_CLIENT=protogreen-wallpaper
MPV_AUDIO="volume=0 audio-client-name=$WP_CLIENT input-ipc-server=$WP_SOCK"
if [ "$MPV_VO" = "gpu" ]; then MPV_OPTS="loop hwdec=vaapi vo=gpu gpu-context=waylandvk $MPV_AUDIO"
else                           MPV_OPTS="loop hwdec=vaapi vo=$MPV_VO $MPV_AUDIO"; fi

current_video() {
    local p=""
    [ -r "$WP_POINTER" ] && p="$(head -1 "$WP_POINTER" 2>/dev/null)"
    [ -n "$p" ] && [ -f "$p" ] && { printf '%s\n' "$p"; return; }
    printf '%s\n' "$DEFAULT_VIDEO"
}
# Match any mpvpaper we own (the wallpaper file changes now, so a filename-specific
# pattern would leak orphans every time you switch wallpapers). "mpvpaper" never
# appears in this script's own cmdline, so pkill -f stays safe.
_video_probe()  { pgrep -x mpvpaper >/dev/null 2>&1; }
# ponytail: same caching as game_running — asked twice a tick.
running_video() { [ "$_video_cached" = 1 ]; }
# -p -a MAX = mpvpaper's own auto-pause: stop presenting while any maximised/fullscreen
# window covers the wallpaper. The 20%-of-a-core present path measured above is real and
# no VO removes it — but it doesn't have to run when nothing can see it.
start_video()   { running_video && return; "${MPV_ENV[@]}" setsid mpvpaper -p -a MAX -o "$MPV_OPTS" "$MON" "$(current_video)" >/dev/null 2>&1 < /dev/null 9>&- & _video_cached=1; }   # 9>&- = don't inherit the flock fd (else fuser -k / lock would catch the wallpaper)
kill_video()    { pkill -x mpvpaper 2>/dev/null; _video_cached=0; }

# Frozen wallpaper for game state. Show one frame of whatever the animated wallpaper
# currently is, so the desktop looks paused rather than swapped: awww draws it on the background layer and then does nothing per-frame, so it
# costs none of the iGPU render the animated wallpaper was killed to free.
# The frame is cached per video (named after its path + mtime, so a re-render or a swap
# from the theme panel makes a new one) and falls back to STATIC if ffmpeg isn't there.
FRAME_DIR="$HOME/.cache/protogreen"
frame_of() {
    local v; v="$(current_video)"
    local key; key="$(printf '%s %s' "$v" "$(stat -c %Y "$v" 2>/dev/null)" | md5sum | cut -c1-16)"
    local f="$FRAME_DIR/wp-frame-$key.png"
    if [ ! -s "$f" ]; then
        mkdir -p "$FRAME_DIR"
        ffmpeg -nostdin -loglevel error -y -i "$v" -frames:v 1 "$f" >/dev/null 2>&1
    fi
    [ -s "$f" ] && printf '%s\n' "$f" || printf '%s\n' "$STATIC"
}
running_static() { pgrep -x awww-daemon >/dev/null 2>&1; }
start_static()   {
    running_static || { setsid awww-daemon >/dev/null 2>&1 </dev/null 9>&- & sleep 0.5; }
    awww img "$(frame_of)" >/dev/null 2>&1
}
kill_static()    { pkill -x awww-daemon 2>/dev/null; }

# Leaving game state = restore the desktop. The game LAUNCHERS (sober-launch.sh,
# beamng.sh) turn Hyprland effects off (`hyprctl keyword animations:enabled 0`) and
# restore them from an EXIT trap — which never runs if the game crashes or the
# launcher is SIGKILLed, leaving animations/blur off until reboot. `hyprctl reload`
# re-reads hyprland.conf (+ the sourced theme.conf) and puts every keyword back,
# whichever launcher died. Safe to run repeatedly: it's an edge, not a poll.
# The wallpaper is force-restarted rather than trusted, because mpvpaper can survive
# as a process while its GL/vaapi context is dead after the dGPU was hammered — pgrep
# sees it alive, the self-heal below never fires, and the screen stays black.
restore_desktop() {
    hyprctl reload >/dev/null 2>&1 || true
    kill_video
    sleep 0.5
}

# ── wallpaper audio ────────────────────────────────────────────────────────────
# Settings live in theme.json (panel writes them). Re-read only when the file's
# mtime moves, so the 3s loop isn't spawning a python interpreter forever.
THEME_JSON="$HOME/.config/protogreen/theme.json"
theme_mtime=""
wp_audio=0          # user wants sound at all
wp_volume=40        # 0..100
load_audio_cfg() {
    local m; m="$(stat -c %Y "$THEME_JSON" 2>/dev/null)" || return 0
    [ "$m" = "$theme_mtime" ] && return 0
    theme_mtime="$m"
    local out
    out="$(python3 -c '
import json,sys
try:
    w=json.load(open(sys.argv[1])).get("wp") or {}
    print(1 if w.get("audio") else 0, max(0,min(100,int(w.get("volume",40)))))
except Exception:
    print(0,40)' "$THEME_JSON" 2>/dev/null)" || return 0
    wp_audio="${out% *}"; wp_volume="${out#* }"
}

mpv_cmd() {   # fire-and-forget; a dead socket is normal right after a restart
    [ -S "$WP_SOCK" ] || return 0
    printf '%s\n' "$1" | timeout 1 socat - "$WP_SOCK" >/dev/null 2>&1 || true
}

# Anything OTHER than the wallpaper actively pushing audio. Corked = the stream
# exists but is paused, which must not count as "playing".
others_playing() {
    pactl list sink-inputs 2>/dev/null | awk -v me="$WP_CLIENT" '
        /^Sink Input #/      { corked=""; app="" }
        /^\tCorked:/         { corked=$2 }
        /application\.name = / { app=$0 }
        /^$/                 { if (corked=="no" && app !~ me && app!="") { print "y"; exit } }
        END                  { if (corked=="no" && app !~ me && app!="") print "y" }' \
        | grep -q y
}

# A fullscreen window means the user is watching/playing something — the wallpaper
# is behind it and its audio is pure noise.
fullscreen_active() {
    [ "$(hyprctl activewindow -j 2>/dev/null | sed -n 's/.*"fullscreen": *\([0-9]*\).*/\1/p' | head -1)" != "0" ] \
      && [ -n "$(hyprctl activewindow -j 2>/dev/null | sed -n 's/.*"fullscreen": *\([0-9]*\).*/\1/p' | head -1)" ]
}

wp_muted=-1
sync_audio() {
    load_audio_cfg
    local want=1
    if [ "$wp_audio" = "1" ] && ! others_playing && ! fullscreen_active; then want=0; fi
    if [ "$want" != "$wp_muted" ]; then
        mpv_cmd "{\"command\":[\"set_property\",\"mute\",$([ "$want" = 1 ] && echo true || echo false)]}"
        wp_muted="$want"
    fi
    # volume is cheap to re-assert and keeps the slider honest after a respawn
    mpv_cmd "{\"command\":[\"set_property\",\"volume\",$wp_volume]}"
}

apply() {
    local want
    if   game_running; then want=game
    elif on_battery;   then want=bat
    else                    want=ac
    fi
    [ "$want" = "$state" ] && return

    [ "$state" = "game" ] && restore_desktop

    case "$want" in
        # SW cursors during games: the HW cursor plane makes WINDOWED games (GMod/Source
        # via Xwayland, Roblox) read an offset cursor position. SW cursor aligns it.
        # HW cursor restored off-game (smooth desktop cursor on the weak UHD).
        # cursor left as SW (no_hardware_cursors=true) always — HW cursor breaks
        # Sober's pointer-lock (camera stuck). Kept out of power state to avoid the
        # grab-time race that stuck the camera on fresh launches.
        game) kill_video; start_static ;;
        bat)  kill_static; set_profile power-saver; start_video ;;
        ac)   kill_static; set_profile balanced;   start_video ;;
    esac
    state=$want
}

wp_seen=""
_game_cached=0
_video_cached=0
CAPTURE_LOCK=/tmp/protogreen-capture.lock
while :; do
    # wpconvert.sh is recording the wallpaper layer: do NOT relaunch mpvpaper on top
    # of the scene it is capturing, and do not fight it for the layer. Clearing
    # wp_seen means the pointer is re-read fresh once the capture is done, so the
    # newly converted wallpaper is picked up instead of the one from before.
    if [ -e "$CAPTURE_LOCK" ]; then
        wp_seen=""
        sleep 3
        continue
    fi
    # one probe per tick each; every helper below reads these
    _game_probe  && _game_cached=1  || _game_cached=0
    _video_probe && _video_cached=1 || _video_cached=0
    apply
    # wallpaper swapped from the theme panel → restart mpvpaper on the new file.
    # (running_video is process-level, so it would happily keep playing the old one.)
    wp_now="$(current_video)"
    if [ "$wp_now" != "$wp_seen" ]; then
        [ -n "$wp_seen" ] && kill_video
        wp_seen="$wp_now"
    fi
    # self-heal: if we're not gaming and the video wallpaper died, bring it back
    # (covers a crash, or a clean login where state hasn't "changed" yet).
    if ! game_running && ! running_video; then start_video; wp_muted=-1; fi
    # same self-heal for the static one: if awww dies mid-game the pet goes black again.
    if game_running && ! running_static; then start_static; fi
    # mute/unmute against what else is making noise or filling the screen
    if running_video; then sync_audio; fi
    sleep 3
done
