import QtQuick
import "../" as App

// Floating bar segment — "smoked glass" build (replaces blur, which was choppy
// over the animated wallpaper). Everything here is STATIC (painted once), so it
// costs nothing per frame: near-opaque tinted gradient fill (no wallpaper bleed),
// frosted noise grain, neon accent edge, scanlines + sheen.
Rectangle {
    id: isle
    default property alias content: inner.data
    property int hpad: 14
    property real spacing: App.Theme.gap

    implicitWidth: inner.implicitWidth + hpad * 2
    implicitHeight: App.Theme.islandH
    radius: App.Theme.islandRadius
    antialiasing: true

    // smoked-glass gradient fill — near-opaque + green-tinted so the busy
    // wallpaper no longer shows through (the reason blur existed). Top lighter →
    // bottom darker also gives the glassy sheen/curvature in one.
    gradient: Gradient {
        GradientStop { position: 0.0; color: App.Theme.chromeTop }
        GradientStop { position: 1.0; color: App.Theme.chromeBot }
    }

    // neon accent edge
    border.width: 1
    border.color: Qt.rgba(App.PowerProfile.accent.r, App.PowerProfile.accent.g, App.PowerProfile.accent.b, 0.7)
    Behavior on border.color { ColorAnimation { duration: 400 } }

    data: [
        // neon halo — a faint accent ring extending just past the edge (fake glow)
        Rectangle {
            anchors.fill: isle
            anchors.margins: -2
            radius: isle.radius + 2
            color: "transparent"
            border.width: 2
            border.color: App.PowerProfile.accent
            opacity: 0.16
            z: 0
        },

        // ── static overlays (clipped to the rounded rect) ──
        Item {
            anchors.fill: isle
            anchors.margins: 1
            clip: true
            z: 1

            // frosted noise grain — painted once, then static
            Canvas {
                id: grain
                anchors.fill: parent
                opacity: 0.05
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var n = Math.floor(width * height / 22)
                    for (var i = 0; i < n; i++) {
                        ctx.fillStyle = (Math.random() > 0.5) ? "#ffffff" : "#000000"
                        ctx.fillRect(Math.floor(Math.random() * width), Math.floor(Math.random() * height), 1, 1)
                    }
                }
                onWidthChanged: requestPaint()
            }

            // CRT scanlines — faint accent lines
            Column {
                anchors.fill: parent
                spacing: 2
                Repeater {
                    model: Math.ceil(isle.implicitHeight / 3)
                    Rectangle {
                        width: parent ? parent.width : 0
                        height: 1
                        color: App.PowerProfile.accentBri
                        opacity: 0.035
                    }
                }
            }

            // top glassy sheen highlight
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: parent.height * 0.5
                radius: isle.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: App.Theme.hairline }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            // bright accent rim along the bottom — neon lift
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: App.PowerProfile.accentBri
                opacity: 0.35
            }
        },

        Row {
            id: inner
            x: isle.hpad
            y: (isle.height - height) / 2
            spacing: isle.spacing
            z: 2
        }
    ]
}
