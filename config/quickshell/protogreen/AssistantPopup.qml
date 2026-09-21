import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "." as App

// Pip's little chat box. The window is a full-screen, input-masked layer (so it
// never blocks the desktop) and the CARD is a plain item moved inside it — that
// makes dragging synchronous and smooth, instead of moving the whole Wayland
// surface every frame (which jittered). Summon via HUD button or SUPER+A.
PanelWindow {
    id: pop
    required property var modelData
    screen: modelData

    visible: App.Bus.assistant && !App.Bus.capture
    color: "transparent"
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }   // full-screen catcher
    WlrLayershell.namespace: "protogreen-ai"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // only the card is clickable; everything else passes through to the desktop
    mask: Region { item: card }

    // copy Pip's reply to the Wayland clipboard
    Process { id: copyProc }
    property bool justCopied: false
    Timer { id: copiedTimer; interval: 1200; onTriggered: pop.justCopied = false }
    function copyReply() {
        if (!App.Assistant.reply) return
        copyProc.command = ["wl-copy", "--", App.Assistant.reply]
        copyProc.running = true
        justCopied = true; copiedTimer.restart()
    }

    readonly property int cardW: 460
    readonly property int cardH: 360
    property real posX: 0
    property real posY: 0
    property bool placed: false

    function center() {
        if (width <= 0 || height <= 0) return
        posX = Math.max(0, (width  - cardW) / 2)
        posY = Math.max(0, (height - cardH) / 2)
        placed = true
    }
    Component.onCompleted: center()
    onWidthChanged: if (!placed) center()
    onVisibleChanged: if (visible) { if (!placed) center(); input.forceActiveFocus(); replyFlick.toBottom() }

    Rectangle {
        id: card
        x: pop.posX
        y: pop.posY
        width: pop.cardW
        height: pop.cardH
        radius: App.Theme.radius
        color: App.Theme.panelDeep
        border.width: 1
        border.color: App.PowerProfile.accent

        transformOrigin: Item.Center
        scale: pop.visible ? 1 : 0.94
        opacity: pop.visible ? 1 : 0
        Behavior on scale { NumberAnimation { duration: App.Theme.anim; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: App.Theme.animF } }

        // faint accent glow ring
        Rectangle {
            anchors.fill: parent; radius: parent.radius; color: "transparent"
            border.width: 1; border.color: App.PowerProfile.accentBri; opacity: 0.12
        }

        Keys.onEscapePressed: App.Bus.assistant = false

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // ── header: face + name + status (also the drag handle) ──
            Item {
                width: parent.width
                height: 40

                // drag anywhere on the header to move the card. Smooth now because
                // the card is a plain item inside a stationary surface (synchronous).
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    property real sx: 0
                    property real sy: 0
                    onPressed: mouse => { sx = mouse.x; sy = mouse.y }
                    onPositionChanged: mouse => {
                        pop.posX = Math.max(0, Math.min(pop.width  - pop.cardW, pop.posX + (mouse.x - sx)))
                        pop.posY = Math.max(0, Math.min(pop.height - pop.cardH, pop.posY + (mouse.y - sy)))
                    }
                }

                Row {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: 10
                Text {
                    id: hface
                    text: App.Assistant.busy ? "◕ᴗ◕" : "◕▿◕"
                    font.family: App.Theme.font; font.pixelSize: 22; font.bold: true
                    color: App.PowerProfile.accentBri
                    transform: Scale { id: hsc; origin.x: hface.width/2; origin.y: hface.height/2; yScale: 1 }
                    Timer {
                        interval: 2600 + Math.random()*3000; running: true; repeat: true
                        onTriggered: { hblink.restart(); interval = 2600 + Math.random()*3000 }
                    }
                    SequentialAnimation {
                        id: hblink
                        NumberAnimation { target: hsc; property: "yScale"; to: 0.1; duration: 70 }
                        NumberAnimation { target: hsc; property: "yScale"; to: 1.0; duration: 130; easing.type: Easing.OutQuad }
                    }
                }
                Column {
                    width: parent.width - hface.width - copyBtn.width - closeBtn.width - 30
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text { text: "Pip"; font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 2
                           font.bold: true; color: App.Theme.fg }
                    Text {
                        text: pop.justCopied ? "copied ✓"
                              : (App.Assistant.busy ? "thinking…"
                              : (App.Assistant.lastAction ? "did: " + App.Assistant.lastAction : "your little visor ^^"))
                        font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 2
                        color: pop.justCopied ? App.PowerProfile.accentBri : App.Theme.muted
                        elide: Text.ElideRight; width: parent.width
                    }
                }
                Text {
                    id: copyBtn
                    visible: App.Assistant.reply !== ""
                    text: "󰆏"
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 1
                    color: pop.justCopied ? App.PowerProfile.accentBri : App.Theme.muted
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                        onClicked: pop.copyReply() }
                }
                Text {
                    id: closeBtn
                    text: "✕"; font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                    color: App.Theme.muted
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor
                        onClicked: App.Bus.assistant = false }
                }
                }   // Row
            }       // Item (header / drag handle)

            Rectangle { width: parent.width; height: 1; color: App.Theme.hairline }

            // ── reply area ──
            Flickable {
                id: replyFlick
                width: parent.width
                height: parent.height - 64 - 44 - 36   // minus header, input, spacing
                clip: true
                contentHeight: replyText.height
                function toBottom() { contentY = Math.max(0, contentHeight - height) }

                TextEdit {
                    id: replyText
                    width: replyFlick.width
                    text: App.Assistant.reply
                          || (App.Assistant.busy ? "" : "hi, i'm Pip ^^ ask me anything, or tell me to do something\n\n• \"open kitty\"\n• \"go to workspace 3\"\n• \"turn on night mode\"\n• \"look up the weather in prague\"")
                    readOnly: true
                    selectByMouse: true
                    persistentSelection: true
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                    color: App.Assistant.reply ? App.Theme.fg : App.Theme.muted
                    selectionColor: App.PowerProfile.accent
                    selectedTextColor: App.Theme.bg
                    onTextChanged: replyFlick.toBottom()
                }
            }

            // ── input ──
            Rectangle {
                width: parent.width; height: 44; radius: App.Theme.pillRadius
                color: App.Theme.surface2
                border.width: 1
                border.color: input.activeFocus ? App.PowerProfile.accent : App.Theme.hairline
                Behavior on border.color { ColorAnimation { duration: App.Theme.animF } }

                TextField {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 44
                    verticalAlignment: TextInput.AlignVCenter
                    placeholderText: App.Assistant.busy ? "…" : "talk to Pip…"
                    enabled: !App.Assistant.busy
                    color: App.Theme.fg
                    placeholderTextColor: App.Theme.muted
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                    background: Item {}
                    onAccepted: {
                        var t = text
                        if (t.trim()) { App.Assistant.send(t); text = "" }
                    }
                }
                // send glyph
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 14 }
                    text: App.Assistant.busy ? "󰔟" : "󰜘"
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 4
                    color: App.PowerProfile.accentBri
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (input.text.trim()) { App.Assistant.send(input.text); input.text = "" } } }
                }
            }
        }
    }
}
