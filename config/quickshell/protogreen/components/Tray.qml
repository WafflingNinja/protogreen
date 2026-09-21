import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Quickshell.Io
import "../" as App

Item {
    id: root
    visible: SystemTray.items.values.length > 0
    implicitWidth: visible ? row.implicitWidth : 0
    implicitHeight: App.Theme.islandH

    // SIGTERM the tray app by its SNI Id (Quickshell exposes .id, not the PID).
    Process { id: killProc }

    // Right-click context menu. One shared popup, retargeted at the clicked icon.
    // (The apps' own SNI menus can't render here — quickshell isn't in
    // QApplication mode — so we offer a direct Terminate instead.)
    PopupWindow {
        id: menu
        property var trayItem: null
        anchor.window: root.QsWindow.window           // the bar window
        implicitWidth: 176
        implicitHeight: card.implicitHeight
        color: "transparent"
        grabFocus: true
        visible: false

        Timer { running: true; interval: 1200; onTriggered: {
            menu.trayItem = SystemTray.items.values.length > 0 ? SystemTray.items.values[0] : null
            menu.anchor.rect = Qt.rect(1700, 40, 1, 1)
            menu.visible = true
            console.log("TRAYDBG opened visible=", menu.visible, "aw=", menu.anchor.window, "h=", menu.implicitHeight)
        }}

        function openAt(item, icon) {
            trayItem = item
            const p = root.QsWindow.itemPosition(icon)   // icon pos in bar-window coords
            anchor.rect = Qt.rect(Math.round(p.x + icon.width - implicitWidth),
                                  Math.round(p.y + icon.height + 6), 1, 1)
            visible = true
        }

        Rectangle {
            id: card
            width: parent.width
            implicitHeight: menuCol.implicitHeight + 8
            radius: App.Theme.pillRadius
            color: App.Theme.panel
            border.width: 1
            border.color: App.PowerProfile.accent

            Column {
                id: menuCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
                spacing: 2

                // header: which app this menu acts on
                Text {
                    anchors { left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 }
                    topPadding: 4; bottomPadding: 4
                    text: menu.trayItem ? (menu.trayItem.title || menu.trayItem.id) : ""
                    elide: Text.ElideRight
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1
                    color: App.Theme.muted
                }

                Rectangle { width: menuCol.width; height: 1; color: App.Theme.hairline }

                Rectangle {
                    id: killRow
                    width: menuCol.width
                    height: 30
                    radius: App.Theme.pillRadius - 2
                    color: ma.containsMouse ? Qt.rgba(0.97, 0.32, 0.29, 0.18) : "transparent"

                    Row {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                        spacing: 9
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""                                      // power-off glyph
                            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 1
                            color: App.Theme.danger
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Terminate"
                            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                            color: App.Theme.danger
                        }
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const it = menu.trayItem
                            menu.visible = false
                            if (!it) return
                            killProc.command = ["bash",
                                Qt.resolvedUrl("../services/tray-kill.sh").toString().replace("file://", ""),
                                it.id]
                            killProc.running = true
                        }
                    }
                }
            }
        }
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Repeater {
            model: SystemTray.items
            delegate: Item {
                id: icon
                required property var modelData
                width: 18; height: 18

                IconImage {
                    anchors.fill: parent
                    source: modelData.icon
                    smooth: true
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) modelData.activate()
                        else menu.openAt(modelData, icon)
                    }
                }
            }
        }
    }
}
