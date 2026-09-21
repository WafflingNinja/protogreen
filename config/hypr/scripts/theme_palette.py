"""PROTO//GREEN palette derivation.

A theme is two gradient stops (a, b). Everything else is derived from stop `a`'s
hue so the whole desktop stays in one colour family, then any key in the theme's
"overrides" map replaces its derived value verbatim.

Kept deliberately small: this is the one place that decides what a theme *means*,
and both the applier and the panel preview import it so they can never disagree.
"""

import colorsys

# Names every managed config template may reference. Order is meaningless; the
# set is what matters — a template placeholder outside this set is a typo, and
# render() raises on it rather than silently emitting an empty string.
KEYS = (
    "bg", "surface", "surface2", "accent", "accent2",
    "bright", "dim", "fg", "muted", "danger", "amber", "bell",
)


def hex2rgb(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def rgb2hex(rgb):
    return "#" + "".join(f"{max(0, min(255, round(c * 255))):02x}" for c in rgb)


def _hls(h):
    r, g, b = hex2rgb(h)
    return colorsys.rgb_to_hls(r, g, b)


def _mk(hue, light, sat):
    return rgb2hex(colorsys.hls_to_rgb(hue % 1.0, max(0.0, min(1.0, light)), max(0.0, min(1.0, sat))))


def derive(a, b, dark=True, overrides=None):
    """Two stops -> the full 12-colour palette.

    Neutrals (bg/surface/fg/muted) take stop `a`'s HUE but their own fixed
    lightness/saturation, which is what keeps a theme readable no matter how
    wild the accent is: a neon-yellow theme still gets a near-black background
    rather than a yellow one.
    """
    ha, la, sa = _hls(a)

    # Accents are used verbatim — the user picked them, don't second-guess.
    #
    # `bright` is the HIGH-CONTRAST accent — it is what highlight text, active
    # glyphs and the lead gradient stop use, so it must contrast against the
    # BACKGROUND, not simply be lighter. On a dark theme that means lifting toward
    # white; on a light theme lifting toward white makes it invisible, so it has to
    # go the other way. `dim` is the low-contrast partner and mirrors it.
    #
    # The 0.17 / 0.21 offsets are calibrated so the reference green accent (#39ff6a)
    # reproduces the hand-picked #90ffa8 / #1fae52 this rice already used.
    if dark:
        bright_l, dim_l = min(0.88, la + 0.17), max(0.18, la - 0.21)
    else:
        bright_l, dim_l = max(0.22, la - 0.24), min(0.72, la + 0.18)

    p = {
        "accent": a,
        "accent2": b,
        "bright": _mk(ha, bright_l, max(0.55, sa)),
        "dim":    _mk(ha, dim_l, max(0.45, sa * 0.70)),
    }

    if dark:
        p["bg"]       = _mk(ha, 0.045, 0.20)
        p["surface"]  = _mk(ha, 0.095, 0.22)
        p["surface2"] = _mk(ha, 0.125, 0.18)
        p["fg"]       = _mk(ha, 0.895, 0.42)
        p["muted"]    = _mk(ha, 0.435, 0.30)
    else:
        p["bg"]       = _mk(ha, 0.955, 0.30)
        p["surface"]  = _mk(ha, 0.900, 0.28)
        p["surface2"] = _mk(ha, 0.855, 0.24)
        p["fg"]       = _mk(ha, 0.130, 0.45)
        p["muted"]    = _mk(ha, 0.480, 0.30)

    # Semantic colours stay semantic: a red danger that turns green with the theme
    # stops meaning "danger". Nudged toward the theme hue only slightly.
    p["danger"] = "#f85149"
    p["amber"]  = "#e3b341"
    # Attention colour (kitty's bell): accent hue pushed BACK toward yellow, the
    # direction that reads as "warning" regardless of where the accent sits.
    p["bell"]   = _mk(ha - 0.175, min(0.80, la + 0.22), 1.0)

    for k, v in (overrides or {}).items():
        if k in KEYS:
            p[k] = v

    missing = set(KEYS) - set(p)
    if missing:
        raise AssertionError(f"palette missing keys: {sorted(missing)}")
    return p


def _self_check():
    """Smallest thing that fails if derivation breaks."""
    p = derive("#39ff6a", "#2fe6a0")
    assert set(p) == set(KEYS), set(p) ^ set(KEYS)
    assert p["accent"] == "#39ff6a" and p["accent2"] == "#2fe6a0"
    for k, v in p.items():
        assert isinstance(v, str) and v.startswith("#") and len(v) == 7, (k, v)

    # Dark themes must actually be dark, and light ones light — the readability
    # guarantee the neutral block above exists to provide.
    for stops in (("#39ff6a", "#2fe6a0"), ("#a855f7", "#f0abfc"), ("#ffe135", "#ff8c00")):
        d = derive(*stops, dark=True)
        assert _hls(d["bg"])[1] < 0.15, (stops, d["bg"])
        assert _hls(d["fg"])[1] > 0.70, (stops, d["fg"])
        l = derive(*stops, dark=False)
        assert _hls(l["bg"])[1] > 0.85, (stops, l["bg"])
        assert _hls(l["fg"])[1] < 0.30, (stops, l["fg"])

        # `bright` is the high-contrast accent: it must stay READABLE against the
        # background in both modes. Lightening it unconditionally made light themes
        # near-white-on-white.
        assert _hls(d["bright"])[1] > _hls(d["bg"])[1] + 0.35, (stops, "dark bright")
        assert _hls(l["bright"])[1] < _hls(l["bg"])[1] - 0.35, (stops, "light bright")
        # and `dim` is its low-contrast partner, on the other side of the accent
        assert _hls(d["dim"])[1] < _hls(d["accent"])[1], stops
        assert _hls(l["dim"])[1] > _hls(l["accent"])[1], stops

    # Overrides win, and unknown keys are ignored rather than corrupting the palette.
    o = derive("#39ff6a", "#2fe6a0", overrides={"muted": "#123456", "nonsense": "#000"})
    assert o["muted"] == "#123456" and "nonsense" not in o

    assert rgb2hex(hex2rgb("#0a0f0c")) == "#0a0f0c"
    assert rgb2hex(hex2rgb("#abc")) == "#aabbcc"
    print("theme_palette self-check OK")


if __name__ == "__main__":
    _self_check()
