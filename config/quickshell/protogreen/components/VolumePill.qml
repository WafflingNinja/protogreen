import QtQuick
import Quickshell.Services.Pipewire
import "../" as App

Item {
    id: root
    property var sink: Pipewire.defaultAudioSink
    property real vol: sink && sink.audio ? sink.audio.volume : 0
    property bool muted: sink && sink.audio ? sink.audio.muted : false
    implicitWidth: row.implicitWidth
    implicitHeight: App.Theme.islandH

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    property string glyph: muted || vol <= 0.001 ? "󰝟"
                          : (vol < 0.34 ? "󰕿" : (vol < 0.67 ? "󰖀" : "󰕾"))

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 1
            color: root.muted ? App.Theme.muted : App.Theme.teal
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.vol * 100) + "%"
            font.family: App.Theme.fontMono; font.pixelSize: App.Theme.fontSize
            color: App.Theme.fg
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onWheel: wheel => {
            if (!root.sink || !root.sink.audio) return
            var step = wheel.angleDelta.y > 0 ? 0.05 : -0.05
            root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + step))
        }
        onClicked: { if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted }
    }
}
