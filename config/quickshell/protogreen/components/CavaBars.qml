import QtQuick
import "../" as App

// Live audio spectrum. Mirror-symmetric green->teal bars.
Row {
    id: root
    property var levels: []
    property int barCount: levels.length
    property real maxHeight: 20
    property color lo: App.PowerProfile.accent
    property color hi: App.Theme.teal
    spacing: 2

    Repeater {
        model: root.barCount
        Rectangle {
            width: 3
            radius: 1.5
            anchors.verticalCenter: parent.verticalCenter
            property real lv: root.levels[index] !== undefined ? root.levels[index] : 0
            height: Math.max(2, lv * root.maxHeight)
            color: Qt.tint(root.lo, Qt.rgba(root.hi.r, root.hi.g, root.hi.b, lv * 0.8))
            opacity: 0.55 + lv * 0.45
            Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
        }
    }
}
