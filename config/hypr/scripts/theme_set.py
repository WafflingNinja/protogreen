#!/usr/bin/env python3
"""Merge changes into theme.json and apply them. The panel's only write path.

Keeping every write behind one script means QML never has to do file IO, the
merge is atomic (temp file + rename, so a crash mid-write cannot leave a
truncated theme.json), and "change the theme" is one testable operation.

  theme_set.py --json '{"a":"#a855f7","b":"#f0abfc"}'   merge + apply
  theme_set.py --json '{...}' --no-apply                merge only
  theme_set.py --save "purple haze"                     snapshot current as a preset
  theme_set.py --load purple-haze                       load a preset + apply
  theme_set.py --list                                   list presets as JSON
  theme_set.py --self-check                             offline checks
"""

import json
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

HOME = os.path.expanduser("~")
STATE = f"{HOME}/.config/protogreen"
THEME_JSON = f"{STATE}/theme.json"
PRESETS = f"{STATE}/themes"

# Only these keys may appear in a theme. An unknown key is dropped rather than
# stored, so a typo from the panel cannot silently accumulate dead state.
ALLOWED = {
    "name", "a", "b", "angle", "animateGradient", "dark", "overrides",
    "font", "fontDelta", "fontSize", "rounding", "gapsIn", "gapsOut",
    "blur", "anim", "barHeight", "opacity", "wp", "kbd", "lock",
}

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

# Numeric fields are clamped, not trusted. These bounds are the same ones the
# panel's sliders use; enforcing them here too means a hand-edited theme.json
# cannot produce a 900px bar or a negative blur that breaks the compositor.
BOUNDS = {
    "angle": (0, 360), "fontDelta": (-6, 12), "fontSize": (6, 32),
    "rounding": (0, 40), "gapsIn": (0, 40), "gapsOut": (0, 80),
    "blur": (0, 10), "anim": (0, 1000), "barHeight": (20, 64),
}


def slug(name):
    s = re.sub(r"[^a-z0-9]+", "-", (name or "untitled").strip().lower()).strip("-")
    return s or "untitled"


def clean(patch):
    """Validate + clamp an incoming patch. Returns only safe, known keys."""
    out = {}
    for k, v in (patch or {}).items():
        if k not in ALLOWED:
            continue
        if k in ("a", "b"):
            if not (isinstance(v, str) and HEX_RE.match(v)):
                raise ValueError(f"{k} must be #rrggbb, got {v!r}")
            out[k] = v.lower()
        elif k in BOUNDS:
            lo, hi = BOUNDS[k]
            out[k] = max(lo, min(hi, int(round(float(v)))))
        elif k == "opacity":
            out[k] = max(0.0, min(1.0, float(v)))
        elif k in ("dark", "animateGradient"):
            out[k] = bool(v)
        elif k == "kbd":
            # Back-compat: `kbd` used to be a plain bool ("follow the theme accent").
            # Old presets and old theme.json files still carry that, so accept it and
            # normalise up rather than throwing their setting away.
            if isinstance(v, bool):
                out[k] = {"mode": "a" if v else "off", "colour": "#39ff6a"}
            elif isinstance(v, dict):
                kb = {}
                m = v.get("mode")
                kb["mode"] = m if m in ("a", "b", "custom", "off") else "a"
                c = v.get("colour")
                kb["colour"] = c.lower() if isinstance(c, str) and HEX_RE.match(c) else "#39ff6a"
                out[k] = kb
            else:
                raise ValueError("kbd must be an object or a bool")
        elif k == "overrides":
            if not isinstance(v, dict):
                raise ValueError("overrides must be an object")
            out[k] = {ok: ov for ok, ov in v.items()
                      if isinstance(ov, str) and HEX_RE.match(ov)}
        elif k == "lock":
            if not isinstance(v, dict):
                raise ValueError("lock must be an object")
            lk = {}
            m = v.get("mode")
            lk["mode"] = m if m in ("wallpaper", "custom", "static", "off") else "wallpaper"
            if "path" in v and isinstance(v["path"], str):
                lk["path"] = v["path"]
            if "frame" in v:
                lk["frame"] = max(0, min(600, int(v["frame"])))
            out[k] = lk
        elif k == "wp":
            if not isinstance(v, dict):
                raise ValueError("wp must be an object")
            wp = {}
            if "fps" in v:      wp["fps"] = max(10, min(120, int(v["fps"])))
            if "seconds" in v:  wp["seconds"] = max(5, min(120, int(v["seconds"])))
            if "crf" in v:      wp["crf"] = max(0, min(40, int(v["crf"])))
            if "audio" in v:    wp["audio"] = bool(v["audio"])
            if "volume" in v:   wp["volume"] = max(0, min(100, int(v["volume"])))
            if "codec" in v and v["codec"] in ("h264", "hevc"):
                wp["codec"] = v["codec"]
            out[k] = wp
        else:
            out[k] = v
    return out


def load():
    with open(THEME_JSON) as fh:
        return json.load(fh)


def write_atomic(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
        os.replace(tmp, path)          # atomic: readers see old or new, never half
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


# Keys whose value is an object. These must MERGE into what's already stored, never
# replace it: setting wp.fps alone must not wipe wp.codec, and loading a preset saved
# before a sub-key existed must not wipe that sub-key's live value. Getting this wrong
# once already silently turned wallpaper sound off.
NESTED = ("wp", "lock", "kbd", "overrides")


def _merge_nested(dst, patch):
    for k in NESTED:
        if k in patch:
            base = dst.get(k)
            if isinstance(base, dict) and isinstance(patch[k], dict):
                merged = dict(base)
                merged.update(patch.pop(k))
                dst[k] = merged
    dst.update(patch)
    return dst


def merge(patch):
    t = _merge_nested(load(), clean(patch))
    write_atomic(THEME_JSON, t)
    return t


def save_preset(name):
    t = load()
    t["name"] = name
    write_atomic(THEME_JSON, t)
    path = f"{PRESETS}/{slug(name)}.json"
    write_atomic(path, t)
    return path


def load_preset(key):
    path = key if os.path.isabs(key) else f"{PRESETS}/{slug(key)}.json"
    with open(path) as fh:
        preset = json.load(fh)
    t = _merge_nested(load(), clean(preset))
    if "name" in preset:
        t["name"] = preset["name"]
    write_atomic(THEME_JSON, t)
    return t


def list_presets():
    out = []
    if os.path.isdir(PRESETS):
        for fn in sorted(os.listdir(PRESETS)):
            if not fn.endswith(".json"):
                continue
            try:
                with open(f"{PRESETS}/{fn}") as fh:
                    d = json.load(fh)
                out.append({"slug": fn[:-5], "name": d.get("name", fn[:-5]),
                            "a": d.get("a", "#39ff6a"), "b": d.get("b", "#2fe6a0")})
            except Exception:
                continue          # a corrupt preset must not break the whole list
    return out


def _self_check():
    assert slug("Purple Haze!") == "purple-haze"
    assert slug("   ") == "untitled"
    assert slug("a//b") == "a-b"

    c = clean({"a": "#A855F7", "rounding": 999, "blur": -4, "opacity": 5,
               "bogus": 1, "angle": 45.6})
    assert c["a"] == "#a855f7", c            # normalised to lower case
    assert c["rounding"] == 40 and c["blur"] == 0, c   # clamped to bounds
    assert c["opacity"] == 1.0 and c["angle"] == 46, c
    assert "bogus" not in c

    # Bad colours are rejected loudly rather than written.
    for bad in ("red", "#xyzxyz", "#fff", 5, None):
        try:
            clean({"a": bad})
        except (ValueError, TypeError):
            pass
        else:
            raise AssertionError(f"accepted bad colour {bad!r}")

    # Overrides keep only valid hex entries.
    o = clean({"overrides": {"muted": "#123456", "junk": "nope"}})["overrides"]
    assert o == {"muted": "#123456"}, o

    # kbd: legacy bool normalises to the object form, so old presets keep working.
    assert clean({"kbd": True})["kbd"]["mode"] == "a"
    assert clean({"kbd": False})["kbd"]["mode"] == "off"
    k = clean({"kbd": {"mode": "custom", "colour": "#AABBCC"}})["kbd"]
    assert k == {"mode": "custom", "colour": "#aabbcc"}, k
    assert clean({"kbd": {"mode": "nonsense"}})["kbd"]["mode"] == "a"

    # lock
    lk = clean({"lock": {"mode": "custom", "path": "/x.mp4", "frame": 9999}})["lock"]
    assert lk == {"mode": "custom", "path": "/x.mp4", "frame": 600}, lk
    assert clean({"lock": {"mode": "junk"}})["lock"]["mode"] == "wallpaper"

    # Every nested block merges instead of replacing.
    got = _merge_nested({"wp": {"fps": 60, "audio": True}, "lock": {"mode": "wallpaper", "frame": 3}},
                        {"wp": {"fps": 30}, "lock": {"mode": "static"}})
    assert got["wp"] == {"fps": 30, "audio": True}, got["wp"]
    assert got["lock"] == {"mode": "static", "frame": 3}, got["lock"]

    # wp clamps and drops unknown codecs.
    wp = clean({"wp": {"fps": 999, "seconds": 1, "crf": 99, "codec": "vp9"}})["wp"]
    assert wp == {"fps": 120, "seconds": 5, "crf": 40}, wp
    wp = clean({"wp": {"audio": 1, "volume": 900}})["wp"]
    assert wp == {"audio": True, "volume": 100}, wp
    assert clean({"wp": {"volume": -5}})["wp"] == {"volume": 0}

    # Loading an OLD preset (one saved before a wp key existed) must not wipe the
    # live wp settings — it silently turned wallpaper sound off once.
    import tempfile as _tf
    d = _tf.mkdtemp()
    global THEME_JSON, PRESETS
    _tj, _pp = THEME_JSON, PRESETS
    try:
        THEME_JSON = f"{d}/theme.json"
        PRESETS = f"{d}/themes"
        write_atomic(THEME_JSON, {"name": "cur", "a": "#39ff6a", "b": "#2fe6a0",
                                  "wp": {"fps": 60, "audio": True, "volume": 40}})
        write_atomic(f"{PRESETS}/old.json", {"name": "old", "a": "#a855f7",
                                             "b": "#f0abfc", "wp": {"fps": 30}})
        got = load_preset("old")
        assert got["a"] == "#a855f7", got
        assert got["wp"]["fps"] == 30, got["wp"]           # preset value wins
        assert got["wp"]["audio"] is True, got["wp"]       # live value survives
        assert got["wp"]["volume"] == 40, got["wp"]
    finally:
        THEME_JSON, PRESETS = _tj, _pp

    print("theme_set self-check OK")


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--self-check" in args:
        _self_check()
        sys.exit(0)

    do_apply = "--no-apply" not in args
    result = None

    if "--json" in args:
        merge(json.loads(args[args.index("--json") + 1]))
    elif "--save" in args:
        result = save_preset(args[args.index("--save") + 1])
    elif "--load" in args:
        load_preset(args[args.index("--load") + 1])
    elif "--list" in args:
        print(json.dumps(list_presets()))
        sys.exit(0)
    else:
        print(__doc__)
        sys.exit(2)

    if do_apply:
        import theme_apply
        theme_apply.apply(verbose=False)
    if result:
        print(result)
