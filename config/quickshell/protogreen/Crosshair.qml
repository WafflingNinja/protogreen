import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as App

// Static crosshair overlay for games (works over fullscreen/borderless/windowed —
// it's an Overlay-layer surface, sits above everything). Fully click/input-through:
// empty mask means the surface never steals mouse or keyboard. Toggle: F4 or HUD button.
PanelWindow {
    id: xhair
    required property var modelData
    screen: modelData

    visible: App.Bus.crosshair && !App.Bus.capture
    color: "transparent"
    exclusiveZone: -1
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "protogreen-crosshair"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}   // empty region — clicks/keys pass straight through to the game

    Item {
        id: center
        anchors.centerIn: parent
        width: 1; height: 1

        property int thickness: 3
        property int length: 7
        property int gap: 3
        property color fill: App.PowerProfile.accentBri

        Rectangle { // top
            width: center.thickness; height: center.length
            color: center.fill; border.width: 1; border.color: "black"
            anchors.horizontalCenter: center.horizontalCenter
            anchors.bottom: center.top; anchors.bottomMargin: center.gap
        }
        Rectangle { // bottom
            width: center.thickness; height: center.length
            color: center.fill; border.width: 1; border.color: "black"
            anchors.horizontalCenter: center.horizontalCenter
            anchors.top: center.bottom; anchors.topMargin: center.gap
        }
        Rectangle { // left
            width: center.length; height: center.thickness
            color: center.fill; border.width: 1; border.color: "black"
            anchors.verticalCenter: center.verticalCenter
            anchors.right: center.left; anchors.rightMargin: center.gap
        }
        Rectangle { // right
            width: center.length; height: center.thickness
            color: center.fill; border.width: 1; border.color: "black"
            anchors.verticalCenter: center.verticalCenter
            anchors.left: center.right; anchors.leftMargin: center.gap
        }
        Rectangle { // center dot
            width: 4; height: 4; radius: 2
            color: center.fill; border.width: 1; border.color: "black"
            anchors.centerIn: center
        }
    }
}
