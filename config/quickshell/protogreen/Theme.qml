pragma Singleton
import QtQuick
import Quickshell
import "." as App

// ── PROTO//GREEN palette ──
// Every name here is now a live binding onto ThemeState, so changing the theme
// (or just dragging the colour wheel) retints the entire shell with no restart
// and no file IO. The names are unchanged from when they were hardcoded, so all
// existing `App.Theme.green` style call sites keep working — "green" simply means
// "the accent" now, whatever hue that currently is.
Singleton {
    readonly property var _p: App.ThemeState.pal

    readonly property color bg:       _p.bg
    readonly property color surface:  _p.surface
    readonly property color surface2: _p.surface2
    readonly property color green:    _p.accent
    readonly property color green2:   _p.dim
    readonly property color greenbri: _p.bright
    readonly property color teal:     _p.accent2
    readonly property color fg:       _p.fg
    readonly property color muted:    _p.muted
    readonly property color danger:   _p.danger
    readonly property color amber:    _p.amber

    // Role aliases — clearer for anything written from here on.
    readonly property color accent:   _p.accent
    readonly property color accent2:  _p.accent2
    readonly property color bright:   _p.bright
    readonly property color dim:      _p.dim

    // translucent panel fills (blur shows through). Alphas match the original
    // hand-tuned values; only the underlying hue moves with the theme.
    readonly property color panel: Qt.rgba(bg.r, bg.g, bg.b, 0.86)
    readonly property color pill:  Qt.rgba(surface.r, surface.g, surface.b, 0.55)
    readonly property color glow:  Qt.rgba(green.r, green.g, green.b, 0.45)

    // Near-opaque surfaces for the floating chrome (bar islands, HUD, OSD, popups).
    // These MUST be derived, not hardcoded: they used to be literal dark rgba values,
    // which left the bar and every popup black in light mode while the text correctly
    // flipped to dark — i.e. invisible.
    readonly property color chromeTop: Qt.rgba(surface.r, surface.g, surface.b, 0.97)
    readonly property color chromeBot: Qt.rgba(bg.r, bg.g, bg.b, 0.98)
    readonly property color panelDeep: Qt.rgba(bg.r, bg.g, bg.b, 0.92)

    // Accent wash used for "this toggle is on" states.
    readonly property color accentWash: Qt.rgba(green.r, green.g, green.b, 0.22)
    readonly property color accentEdge: Qt.rgba(green.r, green.g, green.b, 0.30)

    // Hairline that reads correctly on both light and dark surfaces: white lifts a
    // dark panel, black defines a light one.
    readonly property color hairline: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.10)
    readonly property bool  dark:     App.ThemeState.dark

    // ── geometry (live from the customize sliders) ──
    readonly property int barHeight:    App.ThemeState.barHeight
    readonly property int islandH:      App.ThemeState.barHeight
    readonly property int islandRadius: Math.round(App.ThemeState.rounding)
    readonly property int topMargin:    7
    readonly property int sideMargin:   12
    readonly property int radius:       Math.max(4, Math.round(App.ThemeState.rounding * 0.86))
    readonly property int pillRadius:   Math.max(3, Math.round(App.ThemeState.rounding * 0.71))
    readonly property int gap:          App.ThemeState.gapsIn
    readonly property int pad:          10

    // ── type ──
    readonly property string font:     App.ThemeState.fontFamily
    readonly property string fontMono: App.ThemeState.fontFamily
    readonly property int fontSize:    App.ThemeState.fontSize

    // ── motion ──
    readonly property int anim:  App.ThemeState.anim
    readonly property int animF: Math.max(40, Math.round(App.ThemeState.anim * 0.55))
}
