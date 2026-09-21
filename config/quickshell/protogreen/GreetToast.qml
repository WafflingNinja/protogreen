import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as App

// Pip says hello on login (and by time of day). Shows once, ~4s, then fades.
PanelWindow {
    id: greet
    required property var modelData
    screen: modelData

    anchors { top: true; left: true; right: true }
    implicitHeight: 60
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "protogreen-greet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: !App.Bus.capture
    mask: Region { item: pill }     // only the pill blocks input; rest passes through

    property bool shown: false
    readonly property int hour: new Date().getHours()
    readonly property string greeting: {
        if (hour >= 5  && hour < 12) return "morning, operator ^^"
        if (hour >= 12 && hour < 17) return "afternoon, operator ^^"
        if (hour >= 17 && hour < 22) return "evening, operator ^^"
        return "still up? get some rest soon ◔_◔"
    }

    Component.onCompleted: { shown = true; hideTimer.start() }
    Timer { id: hideTimer; interval: 4200; onTriggered: greet.shown = false }

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: greet.shown ? App.Theme.islandH + App.Theme.topMargin + 10 : -50
        width: row.implicitWidth + 32
        height: 38
        radius: App.Theme.islandRadius
        color: App.Theme.panelDeep
        border.width: 1
        border.color: App.PowerProfile.accent

        opacity: greet.shown ? 1 : 0
        Behavior on y { NumberAnimation { duration: App.Theme.anim; easing.type: Easing.OutBack } }
        Behavior on opacity { NumberAnimation { duration: App.Theme.anim } }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 9
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "◕▿◕"
                font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 4; font.bold: true
                color: App.PowerProfile.accentBri
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: greet.greeting
                font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                color: App.Theme.fg
            }
        }
    }
}
