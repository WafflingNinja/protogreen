import QtQuick
import "../" as App

Rectangle {
    id: root
    property string glyph: ""
    property string label: ""
    property bool on: false
    signal clicked()

    implicitWidth: 74
    implicitHeight: 58
    radius: App.Theme.pillRadius
    color: on ? App.Theme.accentWash : App.Theme.surface2
    border.width: 1
    border.color: on ? App.PowerProfile.accent : App.Theme.hairline
    Behavior on color { ColorAnimation { duration: App.Theme.animF } }

    Column {
        anchors.centerIn: parent
        spacing: 4
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.glyph
            font.family: App.Theme.font
            font.pixelSize: App.Theme.fontSize + 6
            color: root.on ? App.PowerProfile.accentBri : App.Theme.muted
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            font.family: App.Theme.font
            font.pixelSize: App.Theme.fontSize - 2
            color: root.on ? App.Theme.fg : App.Theme.muted
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
