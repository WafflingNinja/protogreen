import QtQuick
import "../" as App

// Horizontal value slider (0..1). Emits moved(value).
Item {
    id: root
    property real value: 0.5
    property string glyph: ""
    signal moved(real v)
    implicitHeight: 26

    Text {
        id: ic
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        font.family: App.Theme.font
        font.pixelSize: App.Theme.fontSize + 2
        color: App.Theme.teal
        width: 22
    }

    Rectangle {
        id: track
        anchors { left: ic.right; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 6; radius: 3
        color: App.Theme.surface2

        Rectangle {
            id: fill
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * Math.max(0, Math.min(1, root.value))
            radius: 3
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: App.PowerProfile.accent }
                GradientStop { position: 1.0; color: App.Theme.teal }
            }
        }
        Rectangle {
            width: 12; height: 12; radius: 6
            color: App.PowerProfile.accentBri
            anchors.verticalCenter: parent.verticalCenter
            x: fill.width - 6
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            function set(mx) {
                var v = Math.max(0, Math.min(1, mx / track.width))
                root.value = v; root.moved(v)
            }
            onPressed: mouse => set(mouse.x)
            onPositionChanged: mouse => { if (pressed) set(mouse.x) }
        }
    }
}
