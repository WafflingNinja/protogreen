import QtQuick
import "../" as App

Item {
    id: root
    implicitWidth: row.implicitWidth
    implicitHeight: App.Theme.islandH

    function tcolor(t) {
        return t >= 85 ? App.Theme.danger : (t >= 70 ? App.Theme.amber : App.PowerProfile.accent)
    }

    component Stat: Row {
        property string glyph
        property string value
        property color tint: App.PowerProfile.accent
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text { text: glyph; font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize; color: parent.tint }
        Text { text: value; font.family: App.Theme.fontMono; font.pixelSize: App.Theme.fontSize - 1; color: App.Theme.fg }
    }
    component Sep: Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "│"; color: App.Theme.muted; font.pixelSize: App.Theme.fontSize
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Stat { glyph: "󰻠"; value: App.Sys.cpu + "%" }
        Sep {}
        Stat { glyph: "󰔏"; value: App.Sys.ctemp + "°"; tint: root.tcolor(App.Sys.ctemp) }
        Sep {}
        Stat { glyph: "󰍛"; value: App.Sys.mem + "%" }
        Sep {}
        Stat { glyph: "󰢮"; value: App.Sys.gpu + "% " + App.Sys.gtemp + "°"; tint: root.tcolor(App.Sys.gtemp) }
    }
}
