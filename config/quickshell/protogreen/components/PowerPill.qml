import QtQuick
import "../" as App

// Visible power-profile selector for the visor right island.
// left-click  = cycle power-saver -> balanced -> performance (writes MANUAL override
//               so power-watch.sh stops auto-switching = no "mixed" profile).
// right-click = auto (clear override, apply power-source default).
// Glyphs are \uXXXX escapes (FontAwesome BMP) so the source stays ASCII-safe.
Item {
    id: pill
    implicitWidth: row.width + 14
    implicitHeight: App.Theme.islandH

    readonly property string p: App.PowerProfile.profile
    readonly property string glyph: p === "performance" ? ""   // bolt
                                   : p === "power-saver" ? ""   // leaf
                                   : ""                          // balance-scale
    readonly property string label: p === "performance" ? "PERF"
                                   : p === "power-saver" ? "SAVE" : "BAL"

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.glyph
            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 2
            color: App.PowerProfile.accentBri
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1; font.bold: true
            color: App.Theme.fg
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => {
            if (m.button === Qt.RightButton) App.PowerProfile.auto()
            else App.PowerProfile.cycle()
        }
    }
}
