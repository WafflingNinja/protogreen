import QtQuick
import "../" as App

// Labelled integer slider for the customize section: "rounding  [──●──]  14".
// Distinct from VSlider (which is a bare 0..1 control for volume/brightness) —
// this one carries a name and shows the real value, because "14" means something
// to you when you are dialling in gaps and a 0..1 fraction does not.
Item {
    id: root

    property string label: ""
    property real from: 0
    property real to: 100
    property real value: 0
    property int decimals: 0
    property string suffix: ""
    signal moved(real v)

    implicitHeight: 30

    readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    Text {
        id: name
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(root.width * 0.30)
        text: root.label
        elide: Text.ElideRight
        font.family: App.Theme.font
        font.pixelSize: App.Theme.fontSize
        color: App.Theme.muted
    }

    Text {
        id: val
        anchors { verticalCenter: parent.verticalCenter; right: parent.right }
        width: 46
        horizontalAlignment: Text.AlignRight
        text: root.value.toFixed(root.decimals) + root.suffix
        font.family: App.Theme.font
        font.pixelSize: App.Theme.fontSize
        color: App.Theme.fg
    }

    Rectangle {
        id: track
        anchors {
            left: name.right; leftMargin: 6
            right: val.left; rightMargin: 8
            verticalCenter: parent.verticalCenter
        }
        height: 5; radius: 3
        color: App.Theme.surface2

        Rectangle {
            id: fill
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * root.frac
            radius: 3
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: App.Theme.dim }
                GradientStop { position: 1.0; color: App.PowerProfile.accent }
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
            anchors.margins: -9
            function set(mx) {
                var f = Math.max(0, Math.min(1, mx / track.width))
                var v = root.from + f * (root.to - root.from)
                if (root.decimals === 0) v = Math.round(v)
                root.value = v
                root.moved(v)
            }
            onPressed: m => set(m.x)
            onPositionChanged: m => { if (pressed) set(m.x) }
        }
    }
}
