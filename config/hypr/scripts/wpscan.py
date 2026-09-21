#!/usr/bin/env python3
"""Enumerate the Wallpaper Engine workshop library for the theme panel's grid.

Emits one JSON array on stdout: id, title, type, preview image path, and whether
a converted mp4 already exists in the cache.

`type` is normalised to lower case because the workshop data is inconsistent
about it — the same library contains "scene", "Scene", "video" and "Video", and
a grid filter that string-matches the raw value silently hides half the library.
"""

import json
import os
import sys

HOME = os.path.expanduser("~")
CACHE = f"{HOME}/.config/protogreen/wallpapers"

# Steam moved its library root over the years; both paths are live on this box
# (one is a symlink to the other on some installs, hence the dedupe by id).
ROOTS = [
    f"{HOME}/.local/share/Steam/steamapps/workshop/content/431960",
    f"{HOME}/.steam/steam/steamapps/workshop/content/431960",
]

PREVIEWS = ("preview.gif", "preview.jpg", "preview.png", "preview.webp", "preview.jpeg")


def scan():
    seen = {}
    for root in ROOTS:
        if not os.path.isdir(root):
            continue
        for wid in os.listdir(root):
            d = os.path.join(root, wid)
            pj = os.path.join(d, "project.json")
            if wid in seen or not os.path.isfile(pj):
                continue
            try:
                with open(pj, encoding="utf-8", errors="replace") as fh:
                    meta = json.load(fh)
            except Exception:
                continue        # a corrupt project.json must not kill the whole scan

            preview = ""
            for name in PREVIEWS:
                p = os.path.join(d, name)
                if os.path.isfile(p):
                    preview = p
                    break

            # Video-type wallpapers already ship a playable file, so they need no
            # conversion at all — mpvpaper can point straight at it. Scene types
            # have to be recorded first, which is what wpconvert.sh is for.
            src = ""
            if os.path.isfile(pj):
                cand = meta.get("file") or ""
                if cand and os.path.isfile(os.path.join(d, cand)):
                    src = os.path.join(d, cand)
                else:
                    for fn in sorted(os.listdir(d)):
                        if fn.lower().endswith((".mp4", ".webm", ".mkv")):
                            src = os.path.join(d, fn)
                            break

            mp4 = os.path.join(CACHE, f"{wid}.mp4")
            seen[wid] = {
                "src": src,
                "id": wid,
                "dir": d,
                "title": meta.get("title") or wid,
                "type": (meta.get("type") or "unknown").strip().lower(),
                "preview": preview,
                "mp4": mp4 if os.path.isfile(mp4) else "",
                # Scene wallpapers expose tweakable user properties; the chat button
                # is only meaningful for those, and the panel uses this to decide
                # whether to offer it.
                "hasProps": bool(meta.get("general", {}).get("properties")),
            }

    out = sorted(seen.values(), key=lambda w: w["title"].lower())
    return out


if __name__ == "__main__":
    if "--self-check" in sys.argv:
        got = scan()
        assert isinstance(got, list)
        for w in got:
            assert set(("id", "dir", "title", "type", "preview", "mp4")) <= set(w)
            assert w["type"] == w["type"].lower()
            assert not w["preview"] or os.path.isfile(w["preview"])
        kinds = {}
        for w in got:
            kinds[w["type"]] = kinds.get(w["type"], 0) + 1
        print(f"wpscan self-check OK — {len(got)} wallpapers, types: {kinds}")
    else:
        json.dump(scan(), sys.stdout)
