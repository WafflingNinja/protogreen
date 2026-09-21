import QtQuick
import Quickshell.Services.UPower
import "../" as App

Item {
    id: root
    property var dev: UPower.displayDevice
    property real pct: dev ? dev.percentage * 100 : 100   // quickshell UPower is 0..1
    property bool charging: dev ? (dev.state === UPowerDeviceState.Charging
                                   || dev.state === UPowerDeviceState.PendingCharge) : false
    visible: dev && dev.isLaptopBattery
    implicitWidth: visible ? row.implicitWidth : 0
    implicitHeight: App.Theme.islandH

    property string glyph: charging ? "󰂄"
                          : (pct >= 90 ? "󰁹" : (pct >= 70 ? "󰂀" : (pct >= 45 ? "󰁾" : (pct >= 20 ? "󰁻" : "󰁺"))))
    property color tint: charging ? App.Theme.teal
                                  : (pct <= 15 ? App.Theme.danger
                                  : (pct <= 30 ? App.Theme.amber : App.PowerProfile.accent))

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 2
            color: root.tint
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.pct) + "%"
            font.family: App.Theme.fontMono; font.pixelSize: App.Theme.fontSize
            color: App.Theme.fg
        }
    }
}
