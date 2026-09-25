#!/usr/bin/env bash
# ── Wallpaper Engine scene → looping mp4, for mpvpaper ──────────────────────────
#
# WHY THIS EXISTS
#   Running linux-wallpaperengine live costs far more than playing a video, so this
#   rice renders each scene to an mp4 once and lets mpvpaper loop it forever. That
#   conversion was previously done by hand and the exact commands were lost; this
#   script is that pipeline, written down.
#
# HOW IT WORKS
#   linux-wallpaperengine draws to the wallpaper layer, so anything floating above
#   it (the visor bar, windows) would be baked into the capture. The bar is therefore
#   taken down and an empty workspace is selected for the duration, then everything
#   is put back by the EXIT trap — including on failure or Ctrl-C, which is why the
#   trap is installed before the first thing that changes state.
#
#   The recording is variable-framerate (that is what wf-recorder produces); the
#   second pass forces constant framerate, because mpvpaper looping a VFR file
#   drifts audibly out of step with itself over time.
#
# LOOPING
#   Scene wallpapers are mostly not periodic, so there is no true loop point to find.
#   Instead the tail is cross-faded back over the head, which turns a hard jump into
#   a short dissolve. --no-crossfade skips it if a given wallpaper looks better cut.
#
# USAGE
#   wpconvert.sh --id 3157997169 [--fps 60] [--seconds 30] [--crf 16]
#                [--codec h264|hevc] [--no-crossfade] [--set] [--keep-raw]
#                [--trim-start S] [--fade S]
#   --set        point the desktop at the result when done
#   --keep-raw   keep the near-lossless capture as <id>.src.mkv so the loop editor
#                can re-cut it later WITHOUT re-recording the scene
#   --reencode   skip recording entirely and re-cut the kept <id>.src.mkv
#                (this is what the loop editor uses)
#   --trim-start seconds to drop from the FRONT before looping
#   --fade       crossfade length in seconds (default 0.6)
set -uo pipefail

ID=""; FPS=60; SECS=30; CRF=16; CODEC=h264; CROSSFADE=1; SETWP=0
KEEPRAW=0; REENCODE=0; TRIMSTART=0
# first output Hyprland reports; eDP-1 only if hyprctl/jq are unavailable
MON="$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // empty' 2>/dev/null)"
: "${MON:=eDP-1}"
CACHE="$HOME/.config/protogreen/wallpapers"
POINTER="$HOME/.config/protogreen/wallpaper.path"
STATEDIR="$HOME/.config/protogreen"
FADE="${FADE:-0.6}"          # crossfade length, seconds (overridable via --fade)

while [ $# -gt 0 ]; do
    case "$1" in
        --id)           ID="$2"; shift 2 ;;
        --fps)          FPS="$2"; shift 2 ;;
        --seconds)      SECS="$2"; shift 2 ;;
        --crf)          CRF="$2"; shift 2 ;;
        --codec)        CODEC="$2"; shift 2 ;;
        --no-crossfade) CROSSFADE=0; shift ;;
        --set)          SETWP=1; shift ;;
        --keep-raw)     KEEPRAW=1; shift ;;
        --reencode)     REENCODE=1; shift ;;
        --trim-start)   TRIMSTART="$2"; shift 2 ;;
        --fade)         FADE="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done
[ -n "$ID" ] || { echo "--id is required" >&2; exit 2; }

# Everything also goes to a log file. The panel launches this as a child of qs, so
# stdout/stderr go nowhere — a failure used to surface as "see journal" with nothing
# in the journal to see. Now there is always a file to read.
LOGFILE="$HOME/.config/protogreen/wpconvert.log"
mkdir -p "$(dirname "$LOGFILE")"
: > "$LOGFILE"
note() { notify-send -a "PROTO//GREEN" "$@" >/dev/null 2>&1 || true; }
log()  { printf '[wpconvert] %s\n' "$*" | tee -a "$LOGFILE"; }
# Fail loudly AND usefully: the reason goes in the notification, not just a log path.
NOTIFIED=0
die()  { log "FAILED: $*"; note "wallpaper convert failed" "$*"; NOTIFIED=1; exit 1; }

for bin in linux-wallpaperengine wf-recorder ffmpeg hyprctl; do
    command -v "$bin" >/dev/null || die "$bin is not installed"
done

# Preflight: the binary existing is not the same as it being able to RUN. An ffmpeg
# upgrade bumps libavcodec's soname and leaves the AUR build of linux-wallpaperengine
# linked against a library that no longer exists — it then dies with exit 127 the
# moment it is launched. Catch that HERE, before the screen has been taken over,
# instead of after hiding the visor and killing the wallpaper.
WE_ERR="$(linux-wallpaperengine --help 2>&1 >/dev/null)"; WE_RC=$?
if [ $WE_RC -ne 0 ] && printf '%s' "$WE_ERR" | grep -q "shared libraries"; then
    MISSING="$(printf '%s' "$WE_ERR" | sed -n 's/.*: \(lib[^:]*\): cannot open.*/\1/p' | head -1)"
    die "linux-wallpaperengine needs ${MISSING:-a missing library} — rebuild it: paru -S --rebuild linux-wallpaperengine-git"
fi

# Refuse to fight a game for the GPU — the capture would be slow AND the game would stutter.
if pgrep -af 'org.vinegarhq.Sober|RobloxPlayer|BeamNG.drive|reaper SteamLaunch|gamescope' 2>/dev/null | grep -qvE 'oworker'; then
    log "refusing to convert: a game is running"
    note "wallpaper convert skipped" "a game is running"
    exit 1
fi

mkdir -p "$CACHE"
OUT="$CACHE/$ID.mp4"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wpconvert.XXXXXX")"
RAW="$TMP/raw.mkv"
# The near-lossless capture, kept next to the mp4 when --keep-raw. The loop editor
# re-cuts THIS instead of re-recording the scene: recording takes over the screen for a
# minute, re-cutting is a few seconds and can be repeated until the seam looks right.
SRC="$CACHE/$ID.src.mkv"

WS_BEFORE="$(hyprctl activeworkspace -j 2>/dev/null | sed -n 's/.*"id": *\([0-9-]*\).*/\1/p' | head -1)"
[ -n "$WS_BEFORE" ] || WS_BEFORE=1

# Hide/show every protogreen surface over IPC.
#
# This used to `pkill -x qs` and restart it. That was fatal: the theme panel launches
# this script as a CHILD of qs, so killing qs killed the conversion too — which is why
# no scene ever finished recording when started from the wallpaper grid. It only ever
# "worked" when run by hand from a shell. Never kill qs from here.
visor() { qs -c protogreen ipc call capture "$1" >/dev/null 2>&1 || true; }

# Tells power-watch.sh to stand down. Without it, its 3s self-heal notices mpvpaper
# is gone (we killed it to free the wallpaper layer) and relaunches it MID-CAPTURE,
# putting the old wallpaper back on the layer we are recording.
CAPTURE_LOCK=/tmp/protogreen-capture.lock

cleanup() {
    local rc=$?
    pkill -x linux-wallpaper 2>/dev/null            # never `pkill -f`: matches this script
    [ -n "${RECPID:-}" ] && kill "$RECPID" 2>/dev/null
    # Puts cursor:inactive_timeout (and anything else we touched) back to what
    # hyprland.conf says, rather than trying to remember the previous value.
    hyprctl reload >/dev/null 2>&1
    hyprctl dispatch workspace "$WS_BEFORE" >/dev/null 2>&1
    visor off
    rm -f "$CAPTURE_LOCK"
    rm -rf "$TMP"
    # Only the generic fallback — die() has already said something specific, and this
    # would otherwise replace a useful message with a useless one.
    [ $rc -ne 0 ] && [ "${NOTIFIED:-0}" = 0 ] && \
        note "wallpaper convert failed" "id $ID — see ~/.config/protogreen/wpconvert.log"
    return $rc
}
trap cleanup EXIT INT TERM

# ── re-cut mode: no recording, no screen takeover ──
# The loop editor calls this. It only needs ffmpeg, so it must NOT hide the visor,
# grab the workspace, or stop the wallpaper — you can keep watching the result change.
if [ "$REENCODE" = 1 ]; then
    trap 'rm -rf "$TMP"' EXIT INT TERM      # replace the full cleanup; nothing was staged
    [ -s "$SRC" ] || die "no kept capture for $ID — re-record it (⟳) first, then it can be re-cut"
    RAW="$SRC"
    log "re-cutting $ID from kept capture  start=${TRIMSTART}s len=${SECS}s fade=${FADE}s"
    note "re-cutting wallpaper" "no re-record needed…"
else

log "converting $ID  ${FPS}fps ${SECS}s crf$CRF $CODEC"
note "converting wallpaper" "recording ${SECS}s at ${FPS}fps…"

# ── stage the clean desktop ──
# Empty scratch workspace first, so no window is on screen when the bar goes down.
hyprctl dispatch workspace 99 >/dev/null 2>&1
touch "$CAPTURE_LOCK"                   # power-watch: hands off the wallpaper until we're done
visor on                                # hide bar/HUD/panel/OSD — layer surfaces, they WOULD be captured
pkill -x mpvpaper 2>/dev/null           # free the wallpaper layer for WE
# wf-recorder has no --no-cursor, and it composites the pointer into every frame —
# a mouse arrow was baked into the first test conversion. Park it in the corner and
# let Hyprland's idle-hide take it away: nothing moves the mouse during an unattended
# capture, so after 1s it is gone. Restored by the `hyprctl reload` in cleanup().
hyprctl keyword cursor:inactive_timeout 1 >/dev/null 2>&1
hyprctl dispatch movecursor 1919 1079 >/dev/null 2>&1
sleep 2

# ── run the scene ──
# --volume 100 (not --silent): the scene's own audio has to be audible for the
# capture to pick it up. Playback volume is set later by power-watch over mpv IPC,
# so recording loud and attenuating at play time keeps the most headroom.
# --noautomute stops WE muting itself the moment anything else makes a sound.
linux-wallpaperengine --screen-root "$MON" --bg "$ID" \
    --scaling fill --fps "$FPS" --volume 100 --noautomute \
    --disable-mouse --no-fullscreen-pause \
    >"$TMP/we.log" 2>&1 &
WEPID=$!
sleep 6                                  # shaders/assets need a moment to settle
if ! kill -0 "$WEPID" 2>/dev/null; then
    tail -20 "$TMP/we.log" >>"$LOGFILE" 2>/dev/null
    die "linux-wallpaperengine exited: $(tail -1 "$TMP/we.log" 2>/dev/null | cut -c1-120)"
fi

# ── capture ──
# Lossless-ish intermediate: the quality decision belongs to the ffmpeg pass, and
# re-encoding a already-lossy capture would compound artefacts.
# --audio records the default sink's monitor. The desktop is deliberately silent at
# this point (bar down, empty workspace), so what lands on the monitor is the scene's
# own audio and nothing else. If the sink has no monitor the recorder would abort, so
# fall back to a video-only capture rather than failing the whole conversion.
AUDIO_ARG=(--audio)
pactl get-default-sink >/dev/null 2>&1 || AUDIO_ARG=()
wf-recorder -o "$MON" -f "$RAW" -c libx264 -p crf=0 -p preset=ultrafast --no-damage \
    "${AUDIO_ARG[@]}" >"$TMP/rec.log" 2>&1 &
RECPID=$!
sleep 2
if ! kill -0 "$RECPID" 2>/dev/null && [ ${#AUDIO_ARG[@]} -gt 0 ]; then
    log "audio capture failed, retrying without audio"; tail -5 "$TMP/rec.log" >&2
    wf-recorder -o "$MON" -f "$RAW" -c libx264 -p crf=0 -p preset=ultrafast --no-damage \
        >"$TMP/rec.log" 2>&1 &
    RECPID=$!
fi
sleep $((SECS + 1))
kill -INT "$RECPID" 2>/dev/null
wait "$RECPID" 2>/dev/null
RECPID=""
pkill -x linux-wallpaper 2>/dev/null

[ -s "$RAW" ] || { tail -20 "$TMP/rec.log" >>"$LOGFILE" 2>/dev/null
    die "wf-recorder produced nothing: $(tail -1 "$TMP/rec.log" 2>/dev/null | cut -c1-120)"; }
log "captured $(du -h "$RAW" | cut -f1)"

if [ "$KEEPRAW" = 1 ]; then
    cp -f "$RAW" "$SRC" && log "kept capture → $SRC ($(du -h "$SRC" | cut -f1))"
fi

fi   # end of the record branch (--reencode jumps straight here)

# ── encode ──
note "converting wallpaper" "encoding…"
if [ "$CODEC" = hevc ]; then VENC=(-c:v libx265 -tag:v hvc1); else VENC=(-c:v libx264 -profile:v high); fi

# `-map 0:a?` keeps the scene's audio when there is any and is a no-op when there
# isn't — plenty of wallpapers are silent, and a hard `-map 0:a` would fail on those.
AENC=(-map 0:v -map "0:a?" -c:a aac -b:a 160k)

# -ss before -i seeks the INPUT, so trimming the front costs nothing and the filter
# graph below still sees a clip that starts at 0.
SEEK=()
awk -v t="$TRIMSTART" 'BEGIN{exit !(t+0 > 0)}' && SEEK=(-ss "$TRIMSTART")

encode_plain() {
    ffmpeg -y "${SEEK[@]}" -i "$RAW" -t "$SECS" -vf "fps=$FPS,format=yuv420p" \
        "${AENC[@]}" "${VENC[@]}" -crf "$CRF" -preset slow -movflags +faststart \
        -shortest "$OUT" >"$TMP/enc.log" 2>&1
}

encode_crossfade() {
    # Dissolve the last $FADE seconds back over the first $FADE seconds:
    #   body = [0 .. SECS-FADE]   tail = [SECS-FADE .. SECS]
    #   out  = (tail blended over body's head) ++ (rest of body)
    local body_end tail_start
    body_end=$(awk -v s="$SECS" -v f="$FADE" 'BEGIN{printf "%.3f", s-f}')
    tail_start="$body_end"
    ffmpeg -y "${SEEK[@]}" -i "$RAW" -an -filter_complex "
        [0:v]fps=$FPS,format=yuv420p,trim=0:$body_end,setpts=PTS-STARTPTS[body];
        [0:v]fps=$FPS,format=yuv420p,trim=$tail_start:$SECS,setpts=PTS-STARTPTS[tail];
        [body]split[b1][b2];
        [b1]trim=0:$FADE,setpts=PTS-STARTPTS[head];
        [b2]trim=$FADE,setpts=PTS-STARTPTS[rest];
        [head][tail]blend=all_expr='A*(1-(T/$FADE))+B*(T/$FADE)',format=yuv420p[mixed];
        [mixed][rest]concat=n=2:v=1:a=0[v]" \
        -map "[v]" -map "0:a?" -c:a aac -b:a 160k -shortest \
        "${VENC[@]}" -crf "$CRF" -preset slow -movflags +faststart \
        "$OUT" >"$TMP/enc.log" 2>&1
}

ok=0
if [ "$CROSSFADE" = 1 ]; then
    encode_crossfade && ok=1
    [ $ok = 1 ] || log "crossfade pass failed, falling back to a plain cut"
fi
[ $ok = 1 ] || { encode_plain && ok=1; }
[ $ok = 1 ] || { tail -25 "$TMP/enc.log" >>"$LOGFILE" 2>/dev/null
    die "ffmpeg failed: $(grep -iE 'error|invalid|no such' "$TMP/enc.log" 2>/dev/null | tail -1 | cut -c1-120)"; }
[ -s "$OUT" ] || die "encode produced no output"

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" 2>/dev/null)
SIZE=$(du -h "$OUT" | cut -f1)
log "done: $OUT  ${DUR}s  $SIZE"

if [ "$SETWP" = 1 ]; then
    mkdir -p "$STATEDIR"
    printf '%s\n' "$OUT" > "$POINTER"      # power-watch.sh polls this and restarts mpvpaper
    # Force the player to reopen the file. power-watch only restarts mpvpaper when the
    # POINTER changes, but a re-cut writes the SAME path with new contents — and the
    # running mpvpaper holds the old data open, so the screen would never update.
    # Killing it lets power-watch's 3s self-heal bring it back on the new file.
    pkill -x mpvpaper 2>/dev/null
    log "set as active wallpaper"
fi

note "wallpaper ready" "$SIZE · ${DUR%.*}s loop"
exit 0
