import QtQuick
import Quickshell.Services.Mpris
import "../" as App

Item {
    id: root
    property var player: {
        var ps = Mpris.players ? Mpris.players.values : []
        for (var i = 0; i < ps.length; i++)
            if (ps[i].playbackState === MprisPlaybackState.Playing) return ps[i]
        return ps.length ? ps[0] : null
    }
    property bool playing: player && player.playbackState === MprisPlaybackState.Playing
    visible: player !== null
    implicitWidth: visible ? row.implicitWidth : 0
    implicitHeight: App.Theme.islandH

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.playing ? "󰎈" : "󰏤"
            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
            color: root.playing ? App.PowerProfile.accentBri : App.Theme.muted
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 220)
            elide: Text.ElideRight
            text: root.player
                  ? ((root.player.trackArtist ? root.player.trackArtist + "  ·  " : "") + (root.player.trackTitle || "—"))
                  : ""
            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
            color: App.Theme.fg
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (!root.player) return
            if (mouse.button === Qt.RightButton) root.player.next()
            else if (mouse.button === Qt.MiddleButton) root.player.previous()
            else root.player.togglePlaying()
        }
    }
}
