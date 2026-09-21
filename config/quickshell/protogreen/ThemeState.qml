pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live theme state for the whole shell.
//
// Two layers on purpose:
//   committed — what ~/.config/protogreen/theme.json currently says, i.e. what the
//               rest of the desktop (kitty, rofi, GTK, hyprland) has been rendered to.
//   pending   — what the panel is currently editing.
//
// Everything in the bar/HUD binds to `pal`, which is derived from PENDING. That is
// what makes dragging the colour wheel recolour the visor instantly and for free:
// no files are touched until you hit apply. The heavy pass (rewriting 15 config
// files + hyprctl reload) only runs on apply(), because doing it per-drag-frame
// would be unusable.
//
// This file never writes anything. All writes go through scripts/theme_set.py so
// the merge stays atomic and validated in one place.
Singleton {
    id: root

    readonly property string scripts: "__HOME__/.config/hypr/scripts"
    readonly property string themePath: "__HOME__/.config/protogreen/theme.json"

    property var committed: ({})
    property var pending: ({})
    property bool busy: false
    property var presets: []

    // Deep-ish equality is overkill here — the panel only mutates via setKey(), so
    // comparing the serialised forms is both correct and cheap.
    readonly property bool dirty: JSON.stringify(committed) !== JSON.stringify(pending)

    // ── convenience accessors (pending) ──
    readonly property string a:  pending.a  ? pending.a  : "#39ff6a"
    readonly property string b:  pending.b  ? pending.b  : "#2fe6a0"
    readonly property int   angle:      pending.angle      !== undefined ? pending.angle      : 45
    readonly property bool  dark:       pending.dark       !== undefined ? pending.dark       : true
    // kbd used to be a bare bool; tolerate that shape so an old theme.json or preset
    // doesn't make the panel read `undefined` everywhere.
    readonly property var   kbdObj: {
        var k = pending.kbd
        if (k === undefined) return ({ mode: "a", colour: "#39ff6a" })
        if (typeof k === "boolean") return ({ mode: k ? "a" : "off", colour: "#39ff6a" })
        return ({ mode: k.mode ? k.mode : "a", colour: k.colour ? k.colour : "#39ff6a" })
    }
    readonly property string kbdMode:   kbdObj.mode
    readonly property string kbdColour: kbdObj.colour
    // What the keys will actually be, given the mode.
    readonly property color kbdEffective: kbdMode === "b"      ? Qt.color(b)
                                        : kbdMode === "custom" ? Qt.color(kbdColour)
                                        : Qt.color(a)

    readonly property var   lock:       pending.lock ? pending.lock : ({ mode: "wallpaper", frame: 3 })
    readonly property string lockMode:  lock.mode ? lock.mode : "wallpaper"
    readonly property bool  animateGrad:pending.animateGradient !== undefined ? pending.animateGradient : false
    readonly property string fontFamily:pending.font       ? pending.font       : "JetBrainsMono Nerd Font"
    readonly property int   fontSize:   pending.fontSize   !== undefined ? pending.fontSize   : 12
    readonly property int   fontDelta:  pending.fontDelta  !== undefined ? pending.fontDelta  : 0
    readonly property int   rounding:   pending.rounding   !== undefined ? pending.rounding   : 14
    readonly property int   gapsIn:     pending.gapsIn     !== undefined ? pending.gapsIn     : 8
    readonly property int   gapsOut:    pending.gapsOut    !== undefined ? pending.gapsOut    : 18
    readonly property int   blur:       pending.blur       !== undefined ? pending.blur       : 0
    readonly property int   anim:       pending.anim       !== undefined ? pending.anim       : 220
    readonly property int   barHeight:  pending.barHeight  !== undefined ? pending.barHeight  : 32
    readonly property real  opacity_:   pending.opacity    !== undefined ? pending.opacity    : 0.86
    readonly property var   wp:         pending.wp         ? pending.wp : ({ fps: 60, seconds: 30, crf: 16, codec: "h264", audio: true, volume: 40 })
    readonly property bool  wpAudio:    wp.audio  !== undefined ? wp.audio  : true
    readonly property int   wpVolume:   wp.volume !== undefined ? wp.volume : 40
    readonly property string themeName: pending.name ? pending.name : "untitled"

    // ── palette derivation — MIRRORS scripts/theme_palette.py ──
    // Any change here must be made there too, or the visor and the rest of the
    // desktop drift apart. Kept as plain HSL maths in both places so they can be
    // compared line by line.
    function _clamp(v) { return Math.max(0, Math.min(1, v)) }
    function _mk(h, l, s) { return Qt.hsla(((h % 1) + 1) % 1, _clamp(s), _clamp(l), 1) }

    function derive(aHex, bHex, isDark, overrides) {
        var c = Qt.color(aHex)
        // hslHue is -1 for achromatic colours; treat those as red so the maths stays finite.
        var ha = c.hslHue < 0 ? 0 : c.hslHue
        var la = c.hslLightness
        var sa = c.hslSaturation

        // `bright` is the HIGH-CONTRAST accent (highlight text, active glyphs, lead
        // gradient stop), so it must contrast with the BACKGROUND rather than just be
        // lighter — on a light theme, lifting it toward white made it invisible.
        var brightL = isDark ? Math.min(0.88, la + 0.17) : Math.max(0.22, la - 0.24)
        var dimL    = isDark ? Math.max(0.18, la - 0.21) : Math.min(0.72, la + 0.18)

        var p = {}
        p.accent  = Qt.color(aHex)
        p.accent2 = Qt.color(bHex)
        p.bright  = _mk(ha, brightL, Math.max(0.55, sa))
        p.dim     = _mk(ha, dimL, Math.max(0.45, sa * 0.70))

        if (isDark) {
            p.bg       = _mk(ha, 0.045, 0.20)
            p.surface  = _mk(ha, 0.095, 0.22)
            p.surface2 = _mk(ha, 0.125, 0.18)
            p.fg       = _mk(ha, 0.895, 0.42)
            p.muted    = _mk(ha, 0.435, 0.30)
        } else {
            p.bg       = _mk(ha, 0.955, 0.30)
            p.surface  = _mk(ha, 0.900, 0.28)
            p.surface2 = _mk(ha, 0.855, 0.24)
            p.fg       = _mk(ha, 0.130, 0.45)
            p.muted    = _mk(ha, 0.480, 0.30)
        }
        p.danger = Qt.color("#f85149")
        p.amber  = Qt.color("#e3b341")
        p.bell   = _mk(ha - 0.175, Math.min(0.80, la + 0.22), 1.0)

        if (overrides)
            for (var k in overrides)
                if (p[k] !== undefined) p[k] = Qt.color(overrides[k])
        return p
    }

    readonly property var pal: derive(a, b, dark, pending.overrides)

    // ── mutation (pending only — nothing on disk moves) ──
    function setKey(k, v) {
        var n = JSON.parse(JSON.stringify(pending))
        n[k] = v
        pending = n
    }
    function setStops(newA, newB) {
        var n = JSON.parse(JSON.stringify(pending))
        n.a = newA; n.b = newB
        pending = n
    }
    function revert() { pending = JSON.parse(JSON.stringify(committed)) }

    // Wallpaper settings are RUNTIME, not theme render settings: power-watch.sh reads
    // sound/volume straight out of theme.json every few seconds. So these write to
    // disk immediately (--no-apply, i.e. no 15-file re-render) instead of waiting for
    // the apply button — toggling sound should just work, not need a full theme apply.
    // Debounced because a volume drag fires this on every frame.
    function setKbd(k, v) {
        var n = JSON.parse(JSON.stringify(kbdObj))
        n[k] = v
        setKey("kbd", n)
    }
    function setLock(k, v) {
        var n = JSON.parse(JSON.stringify(lock))
        n[k] = v
        setKey("lock", n)
    }

    function setWp(k, v) {
        var n = JSON.parse(JSON.stringify(wp))
        n[k] = v
        setKey("wp", n)
        wpFlush.restart()
    }
    Process { id: wpWriter }
    Timer {
        id: wpFlush
        interval: 250
        onTriggered: {
            wpWriter.command = ["python3", root.scripts + "/theme_set.py",
                                "--json", JSON.stringify({ wp: root.wp }), "--no-apply"]
            wpWriter.running = true
        }
    }

    // ── disk ──
    // Set when WE are the one changing the theme on purpose (loading a preset,
    // applying). Without it, the guard below refuses to touch `pending` whenever
    // there are unsaved edits — and since the whole UI renders from `pending`,
    // clicking a preset dot appeared to do nothing at all once you'd nudged
    // anything. Deliberate switches must win over in-flight edits.
    property bool _adopt: false

    function _ingest(raw) {
        try {
            var t = JSON.parse(raw)
            root.committed = t
            // Otherwise: only clobber in-flight edits when there are none, so an
            // unrelated external write can't yank the panel out from under you mid-drag.
            if (_adopt || !root.dirty || Object.keys(root.pending).length === 0) {
                root.pending = JSON.parse(JSON.stringify(t))
                _adopt = false
            }
        } catch (e) {
            console.warn("ThemeState: bad theme.json —", e)
        }
    }

    // Watched, not just read once: theme_set.py can be run straight from a shell
    // (or by another script), and without this the bar would keep painting the old
    // palette while the rest of the desktop had already moved to the new one.
    FileView {
        id: watcher
        path: root.themePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._ingest(watcher.text())
    }
    function reload() { watcher.reload() }

    Process {
        id: applier
        onExited: { root.busy = false; root.reload() }
    }

    function apply() {
        if (busy) return
        busy = true
        _adopt = true                    // committed becomes exactly what we just sent
        applier.command = ["python3", scripts + "/theme_set.py", "--json", JSON.stringify(pending)]
        applier.running = true
    }

    Process {
        id: saver
        onExited: root.refreshPresets()
    }
    function savePreset(name) {
        setKey("name", name)
        // Save must persist the pending edits, not just the name: merge first,
        // then snapshot. --no-apply keeps this cheap; apply() is a separate action.
        var n = JSON.parse(JSON.stringify(pending)); n.name = name
        saver.command = ["sh", "-c",
            "python3 " + scripts + "/theme_set.py --json '" + JSON.stringify(n).replace(/'/g, "'\\''") +
            "' --no-apply && python3 " + scripts + "/theme_set.py --save " + JSON.stringify(name)]
        saver.running = true
    }

    Process {
        id: loader
        onExited: { root.busy = false; root.reload() }
    }
    function loadPreset(slug) {
        if (busy) return
        busy = true
        _adopt = true                    // a preset click must override unsaved edits
        loader.command = ["python3", scripts + "/theme_set.py", "--load", slug]
        loader.running = true
    }

    // A crashed/hung helper would otherwise leave `busy` true forever and every
    // button in the panel silently dead. Release it rather than wedge the UI.
    Timer {
        id: busyGuard
        interval: 90000
        running: root.busy
        onTriggered: {
            console.warn("ThemeState: helper took >90s, releasing busy")
            root.busy = false
        }
    }

    Process {
        id: lister
        command: ["python3", root.scripts + "/theme_set.py", "--list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.presets = JSON.parse(this.text) } catch (e) { root.presets = [] }
            }
        }
    }
    function refreshPresets() { lister.running = true }

    Process {
        id: deleter
        onExited: root.refreshPresets()
    }
    function deletePreset(slug) {
        deleter.command = ["rm", "-f", "__HOME__/.config/protogreen/themes/" + slug + ".json"]
        deleter.running = true
    }

    Component.onCompleted: { reload(); refreshPresets() }
}
