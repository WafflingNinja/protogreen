import QtQuick
import Quickshell
import "../" as App

Item {
    id: root
    implicitWidth: row.implicitWidth
    implicitHeight: App.Theme.islandH
    SystemClock { id: clock; precision: SystemClock.Seconds }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰥔"
            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
            color: App.Theme.teal
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "ddd  HH:mm:ss")
            font.family: App.Theme.fontMono; font.pixelSize: App.Theme.fontSize; font.bold: true
            color: App.Theme.fg
        }
    }
}
