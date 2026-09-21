import QtQuick
import Quickshell
import Quickshell.Io
import "../" as App

// Font picker, as its own view rather than a row in the customize list.
//
// `fc-list` reports 817 "families" on this box, but they are only ~26 actual
// typefaces — the rest are the same face in a different weight or Nerd Font
// packaging (VictorMono alone accounts for 26 names). fontscan.py collapses them,
// so this shows one row per typeface and only reveals the weights when you open one.
Item {
    id: root

    property var groups: []
    property bool loading: true
    property bool monoOnly: true
    property string expanded: ""          // base name of the opened family
    signal closed()

    readonly property string scripts: "__HOME__/.config/hypr/scripts"

    Process {
        id: scanner
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.groups = JSON.parse(this.text) } catch (e) { root.groups = [] }
                root.loading = false
            }
        }
    }
    function refresh() {
        loading = true
        scanner.command = monoOnly ? ["python3", scripts + "/fontscan.py"]
                                   : ["python3", scripts + "/fontscan.py", "--all"]
        scanner.running = true
    }
    onMonoOnlyChanged: refresh()
    Component.onCompleted: refresh()

    // ── header ──
    Item {
        id: head
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 30

        Rectangle {
            id: backBtn
            width: 58; height: 26; radius: App.Theme.pillRadius
            anchors.verticalCenter: parent.verticalCenter
            color: App.Theme.surface2
            border.width: 1; border.color: App.Theme.hairline
            Text {
                anchors.centerIn: parent; text: "‹ back"
                font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1
                color: App.Theme.fg
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: root.closed()
            }
        }

        Text {
            anchors { left: backBtn.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: "font"
            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 1
            font.bold: true
            color: App.PowerProfile.accentBri
        }

        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 78; height: 26; radius: App.Theme.pillRadius
            color: root.monoOnly ? App.PowerProfile.accent : App.Theme.surface2
            border.width: 1; border.color: App.Theme.hairline
            Text {
                anchors.centerIn: parent
                text: root.monoOnly ? "mono only" : "all fonts"
                font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 2
                color: root.monoOnly ? App.Theme.bg : App.Theme.fg
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: root.monoOnly = !root.monoOnly
            }
        }
    }

    Text {
        id: status
        anchors { top: head.bottom; left: parent.left }
        text: root.loading ? "scanning fonts…"
                           : root.groups.length + " families  ·  current: " + App.ThemeState.fontFamily
        font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 2
        color: App.Theme.muted
    }

    ListView {
        id: list
        anchors { top: status.bottom; topMargin: 6; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        spacing: 4
        model: root.groups
        boundsBehavior: Flickable.StopAtBounds

        delegate: Column {
            required property var modelData
            width: list.width
            spacing: 3

            // family row — the name is rendered IN the font, which is the only
            // preview that actually tells you what you are picking.
            Rectangle {
                width: parent.width
                height: 38
                radius: App.Theme.pillRadius
                color: App.ThemeState.fontFamily === modelData.pick
                       || root.expanded === modelData.base ? App.Theme.surface2 : "transparent"
                border.width: 1
                border.color: App.ThemeState.fontFamily.indexOf(modelData.base) === 0
                              ? App.PowerProfile.accent : App.Theme.hairline

                Text {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter
                              right: countTxt.left; rightMargin: 6 }
                    text: modelData.base
                    elide: Text.ElideRight
                    font.family: modelData.pick
                    font.pixelSize: App.Theme.fontSize + 3
                    color: App.Theme.fg
                }
                Text {
                    id: countTxt
                    anchors { right: chevron.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: modelData.variants.length > 1 ? modelData.variants.length + " styles" : ""
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 3
                    color: App.Theme.muted
                }
                Text {
                    id: chevron
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: modelData.variants.length > 1
                          ? (root.expanded === modelData.base ? "⌄" : "›") : ""
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                    color: App.PowerProfile.accentBri
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // Click applies the family's default face immediately; the chevron
                    // area opens the styles. Picking should not require two clicks for
                    // the common case of "just use this font".
                    onClicked: mouse => {
                        if (mouse.x > parent.width - 44 && modelData.variants.length > 1)
                            root.expanded = root.expanded === modelData.base ? "" : modelData.base
                        else
                            App.ThemeState.setKey("font", modelData.pick)
                    }
                }
            }

            // styles, revealed only for the opened family
            Repeater {
                model: root.expanded === parent.modelData.base ? parent.modelData.variants : []
                Rectangle {
                    required property var modelData
                    width: list.width - 18
                    x: 18
                    height: 30
                    radius: App.Theme.pillRadius
                    color: App.ThemeState.fontFamily === modelData
                           ? Qt.rgba(App.PowerProfile.accent.r, App.PowerProfile.accent.g,
                                     App.PowerProfile.accent.b, 0.22) : "transparent"
                    border.width: 1
                    border.color: App.ThemeState.fontFamily === modelData
                                  ? App.PowerProfile.accent : App.Theme.hairline
                    Text {
                        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10
                                  verticalCenter: parent.verticalCenter }
                        text: modelData
                        elide: Text.ElideRight
                        font.family: modelData
                        font.pixelSize: App.Theme.fontSize
                        color: App.ThemeState.fontFamily === modelData ? App.PowerProfile.accentBri : App.Theme.fg
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: App.ThemeState.setKey("font", parent.modelData)
                    }
                }
            }
        }
    }
}
