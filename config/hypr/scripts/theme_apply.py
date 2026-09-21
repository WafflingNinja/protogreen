#!/usr/bin/env python3
"""Apply a PROTO//GREEN theme across the whole desktop.

Two mechanisms, on purpose:

  * Named palette (theme_palette.derive) drives the surfaces that have a small,
    known set of roles: the quickshell bar reads theme.json directly, and
    hypr/theme.conf is generated from the same 12 colours.

  * Hue rotation drives the app configs. Those files carry ~70 distinct shades
    between them (GTK alone derives dozens of tints from its accent), and hand
    mapping every one to a role would be both enormous and lossy. Rotating every
    literal by the same delta recolours all of them, including shades nobody
    enumerated, and preserves the relationships the original theme was designed
    with — a contrast pop stays exactly as far from the accent as it started.

Baselines are pristine copies of the configs as they looked in the reference
green theme. Every apply renders from the baseline, never from the live file, so
switching themes 50 times cannot accumulate rounding drift.

  theme_apply.py                 apply ~/.config/protogreen/theme.json
  theme_apply.py --rebaseline    adopt the CURRENT configs as the new baseline
  theme_apply.py --self-check    run the offline checks and exit
"""

import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import colorsys
from theme_palette import derive, hex2rgb, rgb2hex  # noqa: E402

HOME = os.path.expanduser("~")
CFG = f"{HOME}/.config"
STATE = f"{CFG}/protogreen"
BASE = f"{STATE}/baseline"
THEME_JSON = f"{STATE}/theme.json"

# The reference theme the baselines are written in. Rotation deltas are measured
# against this, so it must match whatever the baseline files actually contain.
REF_ACCENT = "#39ff6a"

# Config files whose colours get rotated. Paths are relative to ~/.config.
MANAGED = [
    "kitty/kitty.conf",
    "kitty/theme.conf",
    "dunst/dunstrc",
    "rofi/config.rasi",
    "rofi/powermenu.rasi",
    "waybar/style.css",
    "hypr/hyprlock.conf",
    "cava/protogreen.conf",
    "fastfetch/config.jsonc",
    "gtk-3.0/gtk.css",
    "gtk-3.0/colors.css",
    "gtk-3.0/thunar.css",
    "gtk-4.0/gtk.css",
    "gtk-4.0/colors.css",
    "gtk-4.0/gtk-dark.css",
]

# Colours that must not rotate. Red means danger in every theme; a "delete"
# button that turns lime because the accent moved is a real usability bug, not a
# style choice. Matched case-insensitively on the 6-digit hex.
PROTECTED = {"f85149", "e65a6e", "ff7b72", "53272c"}

# Every colour literal format that appears across the managed files.
#   #rrggbb   #rrggbbaa   rgb(rrggbb)   rgba(rrggbbaa)   rgba(r, g, b, a)
COLOR_RE = re.compile(
    r"(?P<hyprgba>\brgba\(\s*(?P<hx8>[0-9a-fA-F]{8})\s*\))"
    r"|(?P<hyprgb>\brgb\(\s*(?P<hx6>[0-9a-fA-F]{6})\s*\))"
    r"|(?P<cssrgba>\brgba?\(\s*(?P<r>\d{1,3})\s*,\s*(?P<g>\d{1,3})\s*,\s*(?P<b>\d{1,3})\s*"
    r"(?:,\s*(?P<a>[0-9.]+)\s*)?\))"
    r"|(?P<hash>#(?P<hh>[0-9a-fA-F]{8}|[0-9a-fA-F]{6})\b)"
)


def _shift(hex6, dh, sscale):
    """Rotate one colour's hue, scale its saturation, keep its lightness.

    Lightness is deliberately untouched: it is what makes a dark theme dark, and
    rotating hue must never turn a near-black background into a mid-tone.
    """
    if hex6.lower() in PROTECTED:
        return hex6
    r, g, b = hex2rgb(hex6)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if s < 0.04:                       # neutral grey: rotation is a no-op anyway
        return hex6
    return rgb2hex(colorsys.hls_to_rgb((h + dh) % 1.0, l, max(0.0, min(1.0, s * sscale))))[1:]


def recolor(text, dh, sscale):
    def sub(m):
        if m.group("hyprgba"):
            hx = m.group("hx8")
            return f"rgba({_shift(hx[:6], dh, sscale)}{hx[6:]})"
        if m.group("hyprgb"):
            return f"rgb({_shift(m.group('hx6'), dh, sscale)})"
        if m.group("cssrgba"):
            r, g, b = (int(m.group(k)) for k in ("r", "g", "b"))
            hx = _shift("%02x%02x%02x" % (r, g, b), dh, sscale)
            new = [str(int(hx[i:i + 2], 16)) for i in (0, 2, 4)]
            # Rewrite only the three channel numbers inside the original match, so
            # the author's spacing and the alpha literal survive byte-for-byte.
            # count=3 stops before any digits in the alpha (e.g. the 0 of "0.72").
            it = iter(new)
            return re.sub(r"\d+", lambda _: next(it), m.group(0), count=3)
        hh = m.group("hh")
        new = _shift(hh[:6], dh, sscale)
        # Some GTK sheets write #FFCCCD in caps; keep the author's casing so an
        # unchanged colour stays byte-identical.
        if hh[:6].isupper():
            new = new.upper()
        return "#" + new + hh[6:]
    return COLOR_RE.sub(sub, text)


# The font family used throughout the baseline configs. Family swapping is a plain
# string replace of this name, NOT a directive rewrite: it cannot corrupt syntax,
# and it preserves variant suffixes — "JetBrainsMono Nerd Font Bold" becomes
# "Iosevka Bold" rather than losing its weight.
REF_FONT = "JetBrainsMono Nerd Font"

# Font SIZE is a delta, never an absolute. The configs deliberately use different
# sizes for different things (hyprlock's 72px clock, waybar's 16px/14px modules,
# kitty's 11) and one global number would flatten all of them. A delta shifts the
# whole scale while preserving those relationships. At delta 0 the size pass is
# skipped entirely, which is what makes re-applying the reference theme byte-exact.
# Keyed by the tail of the config path, since each format spells sizes differently.
SIZE_RULES = {
    "kitty/kitty.conf":     [re.compile(r"^(font_size\s+)(\d+)(?:\.\d+)?$", re.M)],
    "hypr/hyprlock.conf":   [re.compile(r"^(\s*font_size\s*=\s*)(\d+)$", re.M)],
    "dunst/dunstrc":        [re.compile(r"^(\s*font\s*=\s*\S.*?\s)(\d+)\s*$", re.M)],
    "rofi/config.rasi":     [re.compile(r'(font:\s*"[^"]*?\s)(\d+)(?=")', re.M)],
    "rofi/powermenu.rasi":  [re.compile(r'(font:\s*"[^"]*?\s)(\d+)(?=")', re.M)],
    "waybar/style.css":     [re.compile(r"(font-size:\s*)(\d+)(?=px)", re.M)],
}


def refont(text, family, delta, rel=""):
    if family != REF_FONT:
        text = text.replace(REF_FONT, family)
    if delta:
        for rx in SIZE_RULES.get(rel, []):
            text = rx.sub(lambda m: m.group(1) + str(max(1, int(m.group(2)) + delta)), text)
    return text


def load_theme():
    with open(THEME_JSON) as fh:
        return json.load(fh)


def rebaseline():
    os.makedirs(BASE, exist_ok=True)
    n = 0
    for rel in MANAGED:
        src = f"{CFG}/{rel}"
        if not os.path.isfile(src):
            continue
        dst = f"{BASE}/{rel}"
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        n += 1
    print(f"baselined {n} files -> {BASE}")


def hypr_conf(t, p):
    """Generated Hyprland override block.

    Sourced at the END of hyprland.conf so it wins on the keys it sets and leaves
    every other line — and every comment — of that file untouched. This also
    survives `hyprctl reload`, which is what power-watch.sh uses to undo a
    crashed game launcher; a theme applied with `hyprctl keyword` alone would be
    silently reverted by that reload.
    """
    ang = int(t.get("angle", 45))
    blur = int(t.get("blur", 0))
    op = float(t.get("opacity", 0.86))
    sh = p["accent"].lstrip("#")
    bgh = p["bg"].lstrip("#")
    ina = p["surface2"].lstrip("#")
    return f"""# ── GENERATED by theme_apply.py — do not edit, edit the theme panel ──
# Sourced at the end of hyprland.conf: last write wins, so only these keys are
# owned by the theme. Everything else in hyprland.conf stays yours.
general {{
    gaps_in = {int(t.get('gapsIn', 8))}
    gaps_out = {int(t.get('gapsOut', 18))}
    col.active_border = rgb({p['bright'].lstrip('#')}) rgb({p['dim'].lstrip('#')}) rgb({p['accent2'].lstrip('#')}) {ang}deg
    col.inactive_border = rgba({ina}aa)
}}

decoration {{
    rounding = {int(t.get('rounding', 14))}
    active_opacity = 1.0
    inactive_opacity = {op:.2f}
    blur {{
        enabled = {'true' if blur > 0 else 'false'}
        size = {max(1, blur)}
        passes = {max(1, min(3, (blur + 1) // 2))}
    }}
    shadow {{
        color = rgba({sh}45)
        color_inactive = rgba({bgh}33)
    }}
}}

animations {{
    enabled = true
    bezier = themeEase, 0.16, 1, 0.3, 1
    animation = windows,     1, {max(1, int(t.get('anim', 220)) // 40)}, themeEase, popin 80%
    animation = fade,        1, {max(1, int(t.get('anim', 220)) // 50)}, themeEase
    animation = workspaces,  1, {max(1, int(t.get('anim', 220)) // 45)}, themeEase, slide
    animation = layers,      1, {max(1, int(t.get('anim', 220)) // 55)}, themeEase, fade
}}
"""


def ensure_source_line():
    """Add the one `source =` line to hyprland.conf, once, at the very end."""
    path = f"{CFG}/hypr/hyprland.conf"
    line = "source = ~/.config/hypr/theme.conf"
    with open(path) as fh:
        body = fh.read()
    if line in body:
        return False
    with open(path, "a") as fh:
        fh.write(
            "\n\n# ── theme panel (SUPER+D → theme) ──\n"
            "# Generated colours/geometry. Sourced LAST so it overrides the look & feel\n"
            "# keys above; every other setting in this file is unaffected.\n"
            f"{line}\n"
        )
    return True


def keyboard_colour(t, p):
    """Which colour the keys should be, or None to leave the keyboard alone.

    `kbd.mode` is one of: a (match gradient stop A) · b (match stop B) ·
    custom (kbd.colour) · off. Old configs stored `kbd` as a bare bool; theme_set.clean
    normalises those, but this also tolerates one arriving raw.
    """
    kb = t.get("kbd", {"mode": "a"})
    if isinstance(kb, bool):
        kb = {"mode": "a" if kb else "off"}
    mode = kb.get("mode", "a")
    if mode == "off":
        return None
    if mode == "b":
        return str(p["accent2"])
    if mode == "custom":
        return kb.get("colour") or str(p["accent"])
    return str(p["accent"])


def set_keyboard(colour):
    """Point the ASUS keyboard backlight at a colour.

    Static single colour via asusctl (the CLI behind ROG Control Center). asusd is a
    system service, so this needs no sudo. Non-fatal by design: on a machine without
    asusctl, or with the daemon down, the theme must still apply.

    NB the FX506HF has a SINGLE-ZONE backlight — the whole keyboard is one colour.
    Per-key/per-zone is not supported by the hardware (`--zone` returns NotSupported).
    """
    if colour is None:
        return "  keyboard: left alone (mode=off)"
    try:
        subprocess.run(["asusctl", "aura", "effect", "static", "-c", colour.lstrip("#")],
                       check=True, capture_output=True, timeout=10)
        return f"  keyboard: {colour}"
    except FileNotFoundError:
        return "  keyboard: skipped (asusctl not installed)"
    except Exception as e:
        return f"  keyboard: skipped ({type(e).__name__})"


LOCK_IMG = f"{STATE}/lock-bg.png"


def set_lock_wallpaper(t):
    """Give hyprlock a background image.

    hyprlock takes a still image, not a video, so "use my wallpaper" means grabbing a
    frame out of the mp4. `lock.mode`:
      wallpaper — a frame from whatever the desktop is currently playing (default)
      custom    — a frame from lock.path (mp4 → frame, image → used as-is)
      static    — the bundled green-furry art
      off       — don't touch hyprlock at all

    The rendered hyprlock.conf comes from the baseline, so its `path =` line is
    rewritten here AFTER that render — otherwise every theme apply would put the
    baseline's path back.
    """
    lk = t.get("lock") or {}
    mode = lk.get("mode", "wallpaper")
    if mode == "off":
        return "  hyprlock: left alone (mode=off)"

    src = ""
    if mode == "static":
        src = f"{HOME}/.config/hypr/wallpapers/green-furry.png"
    elif mode == "custom":
        src = lk.get("path") or ""
    else:
        try:
            with open(f"{STATE}/wallpaper.path") as fh:
                src = fh.readline().strip()
        except OSError:
            src = ""
        if not src or not os.path.isfile(src):
            src = f"{HOME}/.config/hypr/wallpapers/protogen-neon.mp4"

    if not src or not os.path.isfile(src):
        return "  hyprlock: skipped (no source)"

    if src.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
        img = src
    else:
        # Grab a frame a few seconds in — the very first frame of a scene capture is
        # often still fading in from black.
        at = str(max(0, int(lk.get("frame", 3))))
        try:
            subprocess.run(["ffmpeg", "-y", "-ss", at, "-i", src, "-frames:v", "1",
                            "-q:v", "2", LOCK_IMG],
                           check=True, capture_output=True, timeout=60)
        except Exception as e:
            return f"  hyprlock: frame grab failed ({type(e).__name__})"
        img = LOCK_IMG

    path = f"{CFG}/hypr/hyprlock.conf"
    try:
        with open(path) as fh:
            body = fh.read()
    except OSError:
        return "  hyprlock: skipped (no hyprlock.conf)"

    # Only the background{} block's path — hyprlock reuses `path` for other widgets.
    new, n = re.subn(r"(background\s*\{[^}]*?\bpath\s*=\s*)[^\n]*",
                     lambda m: m.group(1) + img, body, count=1, flags=re.S)
    if not n:
        return "  hyprlock: skipped (no background{ path = } to set)"
    with open(path, "w") as fh:
        fh.write(new)
    return f"  hyprlock: {os.path.basename(img)}"


def reload_apps():
    """Nudge each app to re-read what we just wrote. Failures are non-fatal:
    an app that is not running has nothing to reload."""
    out = []

    def run(desc, *cmd):
        try:
            subprocess.run(cmd, check=True, capture_output=True, timeout=10)
            out.append(f"  {desc}: ok")
        except Exception as e:
            out.append(f"  {desc}: skipped ({type(e).__name__})")

    def signal(desc, sig, name):
        rc = subprocess.run(["pkill", sig, "-x", name], capture_output=True, timeout=10).returncode
        out.append(f"  {desc}: {'signalled' if rc == 0 else 'not running'}")

    run("hyprland", "hyprctl", "reload")
    # kitty re-reads its config on SIGUSR1, in place, no restart.
    signal("kitty", "-USR1", "kitty")
    signal("waybar", "-USR2", "waybar")

    # dunst has no reload signal, so it must be restarted. The replacement MUST be
    # fully detached with its stdio on /dev/null: a child that inherits this
    # process's stdout keeps the pipe open after we exit, which hangs whatever is
    # reading our output (it hung a `| head` during development).
    if subprocess.run(["pgrep", "-x", "dunst"], capture_output=True, timeout=10).returncode == 0:
        subprocess.run(["pkill", "-x", "dunst"], capture_output=True, timeout=10)
        devnull = subprocess.DEVNULL
        subprocess.Popen(["dunst"], stdin=devnull, stdout=devnull, stderr=devnull,
                         start_new_session=True)
        out.append("  dunst: restarted")
    else:
        out.append("  dunst: not running")
    # GTK apps pick up gtk.css only on their own restart — nothing to signal.
    out.append("  gtk: applies to newly launched apps")
    return out


def apply(verbose=True):
    t = load_theme()
    a, b = t["a"], t["b"]
    p = derive(a, b, dark=t.get("dark", True), overrides=t.get("overrides") or {})

    rh, _, rs = colorsys.rgb_to_hls(*hex2rgb(REF_ACCENT))
    nh, _, ns = colorsys.rgb_to_hls(*hex2rgb(a))
    dh = nh - rh
    sscale = (ns / rs) if rs > 0.01 else 1.0

    family = t.get("font", REF_FONT)
    delta = int(t.get("fontDelta", 0))

    if not os.path.isdir(BASE):
        raise SystemExit("no baseline yet — run: theme_apply.py --rebaseline")

    written = []
    for rel in MANAGED:
        src, dst = f"{BASE}/{rel}", f"{CFG}/{rel}"
        if not os.path.isfile(src):
            continue
        with open(src, encoding="utf-8", errors="surrogateescape") as fh:
            body = fh.read()
        body = refont(recolor(body, dh, sscale), family, delta, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w", encoding="utf-8", errors="surrogateescape") as fh:
            fh.write(body)
        written.append(rel)

    with open(f"{CFG}/hypr/theme.conf", "w") as fh:
        fh.write(hypr_conf(t, p))
    written.append("hypr/theme.conf")
    if ensure_source_line():
        written.append("hypr/hyprland.conf (added source line)")

    lines = reload_apps()
    lines.append(set_keyboard(keyboard_colour(t, p)))
    lines.append(set_lock_wallpaper(t))

    if verbose:
        print(f"theme '{t.get('name', '?')}'  {a} → {b}   hue {dh * 360:+.0f}°  sat ×{sscale:.2f}")
        print(f"rewrote {len(written)} files:")
        for w in written:
            print(f"  {w}")
        print("reloading:")
        for line in lines:
            print(line)
    return p


def _self_check():
    """Offline checks — no config files touched."""
    # Identity: rotating by zero must change nothing at all.
    sample = ("bg #0a0f0c fg #d4f5df rgba(39ff6a55) rgb(2fe6a0) "
              "rgba(19, 32, 26, 0.85) #90ffa8ff rgba(10,15,12,0.72)")
    assert recolor(sample, 0.0, 1.0) == sample, recolor(sample, 0.0, 1.0)

    # Every format actually gets rewritten when the hue moves.
    rot = recolor(sample, 0.5, 1.0)
    assert rot != sample
    assert rot.count("rgba(") == 3 and rot.count("rgb(") == 1, rot
    # Alpha channels and decimal alphas must survive untouched, and the author's
    # spacing inside rgba(...) must survive too — both spaced and tight forms.
    assert "55)" in rot and "0.85)" in rot and "0.72)" in rot, rot
    assert "rgba(32, 19, 25, 0.85)" in rot and "rgba(15,10,13,0.72)" in rot, rot
    assert re.search(r"#[0-9a-f]{8}\b", rot), rot

    # Lightness is preserved, so dark stays dark.
    dark = recolor("#0a0f0c", 0.4, 1.0).strip("#")
    assert colorsys.rgb_to_hls(*hex2rgb(dark))[1] < 0.12, dark

    # Danger red is protected.
    assert recolor("#f85149", 0.5, 1.0) == "#f85149"
    # Neutral grey is left alone (rotation would be meaningless).
    assert recolor("#808080", 0.5, 1.0) == "#808080"

    # Fonts. Family is a plain replace, so variant suffixes survive.
    assert refont("font_family = JetBrainsMono Nerd Font Bold", "Iosevka", 0) == \
        "font_family = Iosevka Bold"
    # Delta 0 must be a total no-op — this is what guarantees byte-exact re-apply.
    for rel, txt in [("kitty/kitty.conf", "font_size        11.0"),
                     ("hypr/hyprlock.conf", "    font_size = 72"),
                     ("waybar/style.css", "    font-size: 16px;")]:
        assert refont(txt, REF_FONT, 0, rel) == txt, rel
    # Delta shifts each app's own scale, preserving the relationships between them.
    assert refont("font_size        11.0", "x", 2, "kitty/kitty.conf") == "font_size        13"
    assert refont("    font_size = 72", "x", 2, "hypr/hyprlock.conf") == "    font_size = 74"
    assert refont("    font_size = 22", "x", 2, "hypr/hyprlock.conf") == "    font_size = 24"
    assert refont("    font-size: 16px;", "x", 2, "waybar/style.css") == "    font-size: 18px;"
    # dunstrc writes the font unquoted: `font = JetBrainsMono Nerd Font 10`.
    assert refont("    font = JetBrainsMono Nerd Font 10", REF_FONT, 2, "dunst/dunstrc") == \
        "    font = JetBrainsMono Nerd Font 12"
    assert '"JetBrainsMono Nerd Font 13"' in refont(
        '    font:  "JetBrainsMono Nerd Font 11";', REF_FONT, 2, "rofi/config.rasi")
    # A rule must never leak across formats: the kitty pattern must not touch
    # hyprlock's `font_size = 72` (it did, and rewrote it as `font_size 12.0`).
    assert refont("    font_size = 72", "x", 5, "kitty/kitty.conf") == "    font_size = 72"

    # The hyprlock rewrite must hit the background block's `path` and nothing else —
    # hyprlock reuses `path` for other widgets, and clobbering one of those breaks the
    # lockscreen.
    hl = ("background {\n    monitor =\n    path = /old/pic.png\n    blur_passes = 4\n}\n"
          "image {\n    monitor =\n    path = /keep/me.png\n    size = 90\n}\n")
    new, n = re.subn(r"(background\s*\{[^}]*?\bpath\s*=\s*)[^\n]*",
                     lambda m: m.group(1) + "/new/shot.png", hl, count=1, flags=re.S)
    assert n == 1, n
    assert "/new/shot.png" in new and "/keep/me.png" in new and "/old/pic.png" not in new, new
    assert new.count("blur_passes = 4") == 1 and "size = 90" in new

    # keyboard_colour honours each mode, and tolerates the legacy bool.
    pal = derive("#39ff6a", "#2fe6a0")
    assert keyboard_colour({"kbd": {"mode": "a"}}, pal).lower().startswith("#39ff6a")
    assert keyboard_colour({"kbd": {"mode": "b"}}, pal).lower().startswith("#2fe6a0")
    assert keyboard_colour({"kbd": {"mode": "custom", "colour": "#123456"}}, pal) == "#123456"
    assert keyboard_colour({"kbd": {"mode": "off"}}, pal) is None
    assert keyboard_colour({"kbd": True}, pal).lower().startswith("#39ff6a")
    assert keyboard_colour({"kbd": False}, pal) is None
    assert keyboard_colour({}, pal).lower().startswith("#39ff6a")   # default: match A

    # Uppercase hex keeps its casing.
    assert recolor("#FFCCCD", 0.0, 1.0) == "#FFCCCD"
    assert recolor("#FFCCCD", 0.3, 1.0).isupper()

    # A generated hypr block must parse as balanced braces and carry the angle.
    t = {"a": "#39ff6a", "b": "#2fe6a0", "angle": 90, "blur": 4, "rounding": 20}
    blk = hypr_conf(t, derive("#39ff6a", "#2fe6a0"))
    assert blk.count("{") == blk.count("}"), blk
    assert "90deg" in blk and "rounding = 20" in blk and "enabled = true" in blk
    assert "enabled = false" in hypr_conf({"a": "#39ff6a", "b": "#2fe6a0", "blur": 0},
                                          derive("#39ff6a", "#2fe6a0"))
    print("theme_apply self-check OK")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        _self_check()
    elif "--rebaseline" in sys.argv:
        rebaseline()
    else:
        apply()
