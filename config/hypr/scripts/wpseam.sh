#!/usr/bin/env bash
# Extract the two frames that meet at a loop's seam, so the editor can show them
# side by side. If they look the same, the loop is clean; if they don't, you can see
# exactly how far off it is and nudge trim/length until they match.
#
#   wpseam.sh --id <id> [--trim-start S] [--seconds S] [--tag N]
#
# Reads the KEPT capture (<id>.src.mkv) when there is one, else the finished mp4.
# Prints JSON with the source duration (so the editor can bound its sliders to the
# footage that actually exists) and the two output paths.
#
# The frames go to a UNIQUE filename per call, via --tag. Qt caches images by URL and
# treats "?v=2" on a file:// URL as part of the FILENAME, so neither re-setting the
# same path nor a query string reliably reloads a changed file — a fresh path does.
set -uo pipefail

ID=""; TRIMSTART=0; SECS=0; TAG=0
CACHE="$HOME/.config/protogreen/wallpapers"

while [ $# -gt 0 ]; do
    case "$1" in
        --id)         ID="$2"; shift 2 ;;
        --trim-start) TRIMSTART="$2"; shift 2 ;;
        --seconds)    SECS="$2"; shift 2 ;;
        --tag)        TAG="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done
[ -n "$ID" ] || { echo "--id required" >&2; exit 2; }

OUTA="/tmp/protogreen-seam-$TAG-in.png"
OUTB="/tmp/protogreen-seam-$TAG-out.png"
# Drop earlier frames so a long editing session doesn't litter /tmp.
find /tmp -maxdepth 1 -name 'protogreen-seam-*.png' ! -name "*-$TAG-*" -delete 2>/dev/null

SRC="$CACHE/$ID.src.mkv"
[ -s "$SRC" ] || SRC="$CACHE/$ID.mp4"
[ -s "$SRC" ] || { echo "no footage for $ID" >&2; exit 1; }

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC" 2>/dev/null)
DUR=${DUR:-0}

# Clamp the requested window to what the footage actually holds, so dragging a slider
# past the end grabs the last real frame instead of producing an empty image.
read -r A B <<EOF
$(awk -v d="$DUR" -v t="$TRIMSTART" -v s="$SECS" 'BEGIN{
    if (s <= 0) s = d - t;
    a = t; if (a < 0) a = 0; if (a > d) a = d;
    b = t + s; if (b > d) b = d; if (b < a) b = a;
    if (b > 0.05) b -= 0.05;          # last real frame, not one past the end
    printf "%.3f %.3f", a, b
}')
EOF

grab() { ffmpeg -y -ss "$1" -i "$SRC" -frames:v 1 -q:v 3 "$2" >/dev/null 2>&1; }
grab "$A" "$OUTA"
grab "$B" "$OUTB"

# The editor reads this; report what it needs to lay out its sliders and load frames.
printf '{"duration":%s,"in":%s,"out":%s,"kept":%s,"inFile":"%s","outFile":"%s"}\n' \
    "$DUR" "$A" "$B" \
    "$([ -s "$CACHE/$ID.src.mkv" ] && echo true || echo false)" \
    "$OUTA" "$OUTB"
