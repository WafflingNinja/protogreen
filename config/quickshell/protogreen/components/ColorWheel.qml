import QtQuick
import "../" as App

// HSV colour disc: hue around the circumference, saturation toward the rim.
// Lightness is a separate slider — cramming it in as a third dimension makes a
// disc that is hard to aim, and lightness is the one axis you usually want to
// nudge on its own anyway.
//
// The disc is painted ONCE into an ImageData and cached. Repainting ~90k pixels
// from QML JS on every drag frame would make the wheel unusable; the cached
// image means dragging only moves a marker.
Item {
    id: root

    property color value: "#39ff6a"
    property real lightness: 0.6
    signal picked(color c)

    implicitWidth: 190
    implicitHeight: 190

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real rad: Math.min(width, height) / 2 - 2

    Canvas {
        id: disc
        anchors.fill: parent
        // The disc is drawn at full saturation/value; the lightness slider dims the
        // whole thing via the overlay below, which keeps the hue/sat geometry stable
        // while you drag lightness.
        //
        // The pixels are cached as ImageData and re-blitted on every paint. An earlier
        // version skipped painting entirely once done, which left the wheel BLANK
        // after the panel was closed and reopened — the window is unmapped in between
        // and the canvas loses its contents, so "already painted" is not a safe guard.
        property var cache: null

        onPaint: {
            var ctx = getContext("2d")
            var w = Math.floor(width), h = Math.floor(height)
            if (w <= 0 || h <= 0) return
            if (cache) { ctx.drawImage(cache, 0, 0); return }
            var img = ctx.createImageData(w, h)
            var d = img.data
            var ccx = w / 2, ccy = h / 2, rr = Math.min(w, h) / 2 - 2

            for (var y = 0; y < h; ++y) {
                for (var x = 0; x < w; ++x) {
                    var dx = x - ccx, dy = y - ccy
                    var dist = Math.sqrt(dx * dx + dy * dy)
                    var i = (y * w + x) * 4
                    if (dist > rr) { d[i + 3] = 0; continue }

                    var hue = (Math.atan2(dy, dx) / (2 * Math.PI) + 1.0) % 1.0
                    var sat = Math.min(1, dist / rr)
                    var c = Qt.hsva(hue, sat, 1.0, 1.0)
                    d[i]     = Math.round(c.r * 255)
                    d[i + 1] = Math.round(c.g * 255)
                    d[i + 2] = Math.round(c.b * 255)
                    // Feather the last pixel ring so the edge is not stair-stepped.
                    d[i + 3] = dist > rr - 1.5 ? Math.round(255 * (rr - dist) / 1.5) : 255
                }
            }
            cache = img
            ctx.drawImage(img, 0, 0)
        }
        Component.onCompleted: requestPaint()
        onWidthChanged: { cache = null; requestPaint() }
        // Remapping the window clears the canvas; repaint whenever it becomes visible.
        onVisibleChanged: if (visible) requestPaint()
    }

    // Darkening veil driven by the lightness slider, so the disc previews roughly
    // what you will actually get.
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#000000"
        opacity: Math.max(0, 0.55 - root.lightness * 0.55)
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)
    }

    // marker
    Rectangle {
        id: marker
        width: 14; height: 14; radius: 7
        color: root.value
        border.width: 2
        border.color: "#ffffff"
        antialiasing: true
        x: root.cx + root.rad * Math.min(1, root.value.hsvSaturation)
              * Math.cos(root.value.hsvHue * 2 * Math.PI) - width / 2
        y: root.cy + root.rad * Math.min(1, root.value.hsvSaturation)
              * Math.sin(root.value.hsvHue * 2 * Math.PI) - height / 2
        visible: root.value.hsvHue >= 0
    }

    MouseArea {
        anchors.fill: parent
        function pick(mx, my) {
            var dx = mx - root.cx, dy = my - root.cy
            var dist = Math.sqrt(dx * dx + dy * dy)
            // Clamp to the rim instead of ignoring the drag — dragging past the
            // edge should keep tracking the hue, not freeze.
            var sat = Math.min(1, dist / root.rad)
            var hue = (Math.atan2(dy, dx) / (2 * Math.PI) + 1.0) % 1.0
            var c = Qt.hsla(hue, sat, root.lightness, 1.0)
            root.value = c
            root.picked(c)
        }
        onPressed: m => pick(m.x, m.y)
        onPositionChanged: m => { if (pressed) pick(m.x, m.y) }
    }
}
