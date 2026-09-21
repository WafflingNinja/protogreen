import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as App
import "components" as C

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    anchors { top: true; left: true; right: true }
    implicitHeight: App.Theme.islandH + App.Theme.topMargin + 8
    color: "transparent"
    exclusiveZone: App.Theme.islandH + App.Theme.topMargin
    WlrLayershell.namespace: "protogreen-bar"
    WlrLayershell.layer: WlrLayer.Top
    visible: !App.Bus.capture

    function wsOccupied(n) { return App.Compositor.wsOccupied(n) }
    property int focusedWs: App.Compositor.focusedWs
    onFocusedWsChanged: glitch.restart()

    // boot power-on: islands flicker up from dark, a scan sweeps across, eyes wake
    property real bootOpacity: 0
    Component.onCompleted: boot.start()

    // island-height divider
    component Div: Item {
        implicitWidth: 1; implicitHeight: App.Theme.islandH
        Rectangle { anchors.centerIn: parent; width: 1; height: 16; color: App.Theme.muted; opacity: 0.35 }
    }
    // island-height centered wrapper for short widgets
    component Center: Item {
        default property alias kid: holder.data
        implicitWidth: holder.childrenRect.width
        implicitHeight: App.Theme.islandH
        Item { id: holder; anchors.centerIn: parent; width: childrenRect.width; height: childrenRect.height }
    }

    // ════════ LEFT ISLAND — mood face + eyes ════════
    C.Island {
        id: leftIsle
        opacity: bar.bootOpacity
        anchors { left: parent.left; leftMargin: App.Theme.sideMargin; top: parent.top; topMargin: App.Theme.topMargin }
        transform: Translate { id: leftShake; x: 0 }

        C.MoodFace {}
        Div {}
        Center {
            Row {
                spacing: 4
                Repeater {
                    model: 6
                    C.VisorEye {
                        wsId: index + 1
                        active: bar.focusedWs === (index + 1)
                        occupied: bar.wsOccupied(index + 1)
                    }
                }
            }
        }
    }

    // ════════ CENTER ISLAND — media · cava · clock ════════
    C.Island {
        id: centerIsle
        opacity: bar.bootOpacity
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: App.Theme.topMargin }

        C.MediaPill {}
        Center {
            C.CavaBars {
                levels: App.Cava.levels
                maxHeight: 20
                lo: App.PowerProfile.accent
                hi: App.Theme.teal
            }
        }
        C.Clock {}
    }

    // ════════ RIGHT ISLAND — tray · sys · vol · batt · core ════════
    C.Island {
        id: rightIsle
        opacity: bar.bootOpacity
        anchors { right: parent.right; rightMargin: App.Theme.sideMargin; top: parent.top; topMargin: App.Theme.topMargin }

        C.Tray {}
        C.SysInfo {}
        Div {}
        C.VolumePill {}
        C.BatteryPill {}
        Div {}
        C.PowerPill {}
        Center {
            Rectangle {
                id: core
                width: 26; height: 22; radius: App.Theme.pillRadius
                color: App.Bus.hud ? App.PowerProfile.accent
                       : Qt.rgba(App.PowerProfile.accent.r, App.PowerProfile.accent.g, App.PowerProfile.accent.b, 0.16)
                border.width: 1
                border.color: Qt.rgba(App.PowerProfile.accent.r, App.PowerProfile.accent.g, App.PowerProfile.accent.b, 0.5)
                Behavior on color { ColorAnimation { duration: 250 } }
                Text {
                    anchors.centerIn: parent
                    text: "󰊠"
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 2
                    color: App.Bus.hud ? App.Theme.bg : App.PowerProfile.accentBri
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) App.Compositor.exec("__HOME__/.config/hypr/scripts/powermenu.sh")
                        else if (mouse.button === Qt.MiddleButton) App.PowerProfile.cycle()
                        else App.Bus.toggleHud()
                    }
                }
            }
        }
    }

    // ════════ BOOT POWER-ON (runs once at login) ════════
    Rectangle {
        id: bootScan
        width: 4; height: App.Theme.islandH + 8
        y: App.Theme.topMargin - 4
        x: 0
        color: App.PowerProfile.accentBri
        opacity: 0
        radius: 2
    }
    SequentialAnimation {
        id: boot
        PropertyAction { target: bar; property: "bootOpacity"; value: 0 }
        PauseAnimation { duration: 140 }
        // flicker to life
        NumberAnimation { target: bar; property: "bootOpacity"; to: 0.55; duration: 45 }
        NumberAnimation { target: bar; property: "bootOpacity"; to: 0.08; duration: 55 }
        NumberAnimation { target: bar; property: "bootOpacity"; to: 0.7;  duration: 40 }
        NumberAnimation { target: bar; property: "bootOpacity"; to: 0.18; duration: 50 }
        // scan sweep + full power on together
        ParallelAnimation {
            NumberAnimation { target: bar; property: "bootOpacity"; to: 1.0; duration: 280; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PropertyAction  { target: bootScan; property: "opacity"; value: 0.9 }
                NumberAnimation { target: bootScan; property: "x"; from: 0; to: bar.width; duration: 360; easing.type: Easing.InOutQuad }
                PropertyAction  { target: bootScan; property: "opacity"; value: 0 }
            }
        }
        // eyes blink awake
        ScriptAction { script: glitch.restart() }
    }

    // ════════ GLITCH TRANSITION (visor 'reboot' on workspace switch) ════════
    Rectangle {
        id: glitchFlash
        x: leftIsle.x; y: leftIsle.y
        width: leftIsle.width; height: leftIsle.height
        radius: App.Theme.islandRadius
        color: App.PowerProfile.accent
        opacity: 0
    }
    Rectangle {
        id: glitchScan
        x: leftIsle.x; width: leftIsle.width; height: 3
        color: App.PowerProfile.accentBri
        opacity: 0; y: leftIsle.y
    }
    SequentialAnimation {
        id: glitch
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: glitchFlash; property: "opacity"; to: 0.28; duration: 35 }
                NumberAnimation { target: glitchFlash; property: "opacity"; to: 0.0;  duration: 55 }
                NumberAnimation { target: glitchFlash; property: "opacity"; to: 0.16; duration: 35 }
                NumberAnimation { target: glitchFlash; property: "opacity"; to: 0.0;  duration: 70 }
            }
            SequentialAnimation {
                PropertyAction  { target: glitchScan; property: "opacity"; value: 0.9 }
                NumberAnimation { target: glitchScan; property: "y"; from: leftIsle.y; to: leftIsle.y + leftIsle.height; duration: 180; easing.type: Easing.InQuad }
                PropertyAction  { target: glitchScan; property: "opacity"; value: 0.0 }
            }
            SequentialAnimation {
                NumberAnimation { target: leftShake; property: "x"; to: -2; duration: 30 }
                NumberAnimation { target: leftShake; property: "x"; to: 3;  duration: 40 }
                NumberAnimation { target: leftShake; property: "x"; to: 0;  duration: 40 }
            }
        }
    }
}
