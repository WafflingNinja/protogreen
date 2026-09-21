#!/usr/bin/env python3
"""Group the installed font families into real families + their variants.

`fc-list` reports every patched weight and every Nerd Font packaging as its own
"family": JetBrainsMono alone yields 48 names (NF / NFM / NFP / NL x Thin..ExtraBold).
Listing those raw is unusable to pick from. This collapses them to one entry per
actual typeface, with the variants kept underneath.

Emits JSON: [{"base","mono","pick","variants":[...]}, ...]
  base     the family name to show      e.g. "JetBrainsMono"
  pick     the variant to use if you choose the family without expanding it
  variants every real family name that rolls up to this base
"""

import json
import re
import subprocess
import sys

# Nerd Font packaging suffixes. Longest first — "Nerd Font Mono" must be stripped
# before "Nerd Font", or the trailing "Mono" survives and splits the family in two.
NERD = [
    " Nerd Font Propo", " Nerd Font Mono", " Nerd Font",
    " NFP", " NFM", " NF",
]

# Weight / style tokens fontconfig appends to the family name. Nerd Font builds also
# use ABBREVIATED forms (Obl, SemBd, Med, Ret, Cond) — without those, VictorMono alone
# splits into 13 separate "families". Words that are part of a real family name
# ("Mono", "Sans", "Term") must never appear here.
STYLE = {
    "thin", "extralight", "ultralight", "light", "regular", "book", "text",
    "medium", "semibold", "demibold", "bold", "extrabold", "ultrabold", "black",
    "heavy", "italic", "oblique", "condensed", "semicondensed", "expanded",
    "retina", "roman", "semilight",
    # abbreviations
    "obl", "med", "sembd", "ret", "cond", "bd", "lt", "blk", "thn", "xlt",
    "extbd", "it", "bdit", "semlt", "extlt",
    # leading halves of two-word styles ("Demi Bold", "Extra Bold")
    "demi", "extra", "semi", "ultra",
}

# Icon / symbol / pictograph fonts — never a sensible choice for UI text, and several
# of them report as monospaced so the spacing filter alone does not exclude them.
JUNK = ("symbols", "emoji", "material icons", "material design icons", "joypixels",
        "signwriting", "font awesome", "weather icons", "octicons", "codicon")


def families():
    out = subprocess.run(["fc-list", ":", "family"], capture_output=True, text=True).stdout
    names = set()
    for line in out.splitlines():
        for part in line.split(","):
            p = part.strip()
            if p:
                names.add(p)
    return names


def mono_families():
    out = subprocess.run(["fc-list", ":spacing=100", "family"],
                         capture_output=True, text=True).stdout
    names = set()
    for line in out.splitlines():
        for part in line.split(","):
            p = part.strip()
            if p:
                names.add(p)
    return names


def base_of(name):
    # Peel from the END until nothing more comes off. A single pass is not enough:
    # the packaging marker and the weight interleave ("JetBrainsMono NFP ExtraBold"),
    # so stripping only the suffix, or only the styles, leaves half the tail behind.
    s = name
    while True:
        before = s
        words = s.split()
        while len(words) > 1 and words[-1].lower() in STYLE:
            words.pop()
        s = " ".join(words)
        for suf in NERD:
            if s.endswith(suf):
                s = s[: -len(suf)]
                break
        if s == before or not s:
            break
    return s or name


def rank(variant, base):
    """Lower sorts first. Prefer the plain Nerd Font build of a family — it has the
    glyphs the bar needs, without the Mono/Propo spacing quirks."""
    v = variant.lower()
    if variant == base + " Nerd Font":
        return 0
    if variant == base:
        return 1
    if v.endswith("nerd font mono"):
        return 2
    if v.endswith("nerd font propo"):
        return 3
    if any(w in v for w in ("nf", "nerd")):
        return 4
    return 5


def scan(mono_only=True):
    allf = families()
    monof = mono_families()
    pool = monof if mono_only else allf

    groups = {}
    for name in pool:
        low = name.lower()
        if any(j in low for j in JUNK):
            continue
        groups.setdefault(base_of(name), []).append(name)

    out = []
    for base, variants in groups.items():
        variants.sort(key=lambda v: (rank(v, base), len(v), v))
        out.append({
            "base": base,
            "mono": base in {base_of(m) for m in monof},
            "pick": variants[0],
            "variants": variants,
        })
    out.sort(key=lambda g: g["base"].lower())
    return out


def _self_check():
    assert base_of("JetBrainsMono Nerd Font") == "JetBrainsMono"
    assert base_of("JetBrainsMono Nerd Font Mono") == "JetBrainsMono"
    assert base_of("JetBrainsMono NFP ExtraBold") == "JetBrainsMono"
    assert base_of("JetBrainsMono NF Thin") == "JetBrainsMono"
    assert base_of("VictorMono Nerd Font SemiBold Italic") == "VictorMono"
    assert base_of("Inter") == "Inter"
    # "Mono" is part of the name here, not a suffix — must survive.
    assert base_of("Martian Mono") == "Martian Mono"
    assert base_of("IntelOne Mono Nerd Font") == "IntelOne Mono"
    # A family that is only a style word must not collapse to nothing.
    assert base_of("Black") == "Black"

    g = scan(mono_only=True)
    assert g, "no families found"
    for e in g:
        assert e["pick"] in e["variants"]
        assert e["base"]
    names = {e["base"] for e in g}
    assert "JetBrainsMono" in names, sorted(names)[:40]
    jb = next(e for e in g if e["base"] == "JetBrainsMono")
    assert jb["pick"] == "JetBrainsMono Nerd Font", jb["pick"]
    assert len(jb["variants"]) > 5
    # Abbreviated styles must collapse too — VictorMono's "NF Thin Obl", "NFM Med"
    # etc. previously produced 13 separate one-variant "families".
    assert len([e for e in g if e["base"].startswith("VictorMono")]) == 1, \
        [e["base"] for e in g if e["base"].startswith("VictorMono")]
    # No icon font may survive into a font picker.
    assert not [e for e in g if any(j in e["base"].lower() for j in JUNK)]
    # Non-mono families appear only with --all.
    assert "Inter" in {e["base"] for e in scan(mono_only=False)}
    total = sum(len(e["variants"]) for e in g)
    print(f"fontscan self-check OK — {len(g)} families from {total} raw names")


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        _self_check()
    else:
        json.dump(scan(mono_only="--all" not in sys.argv), sys.stdout)
