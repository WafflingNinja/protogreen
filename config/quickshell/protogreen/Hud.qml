import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "." as App
import "components" as C

PanelWindow {
    id: hud
    required property var modelData
    screen: modelData

    visible: App.Bus.hud && !App.Bus.capture
    anchors { top: true; right: true; bottom: true }
    implicitWidth: 380
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "protogreen-hud"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // ── state polling (only while open) ──
    property bool nightOn: false
    property bool wifiOn: true
    property bool btOn: false
    property bool clickerOn: false
    property bool idlerOn: false
    property real bright: 0.5

    Process { id: pNight; command: ["sh","-c","pgrep -x " + App.Compositor.nightProc + " >/dev/null && echo 1 || echo 0"]
        stdout: SplitParser { onRead: l => hud.nightOn = (l.trim() === "1") } }
    Process { id: pWifi; command: ["sh","-c","nmcli -t radio wifi 2>/dev/null"]
        stdout: SplitParser { onRead: l => hud.wifiOn = (l.trim() === "enabled") } }
    Process { id: pBt; command: ["sh","-c","bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo 1 || echo 0"]
        stdout: SplitParser { onRead: l => hud.btOn = (l.trim() === "1") } }
    Process { id: pBright; command: ["sh","-c","brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'"]
        stdout: SplitParser { onRead: l => { var v = parseInt(l); if (!isNaN(v)) hud.bright = v/100 } } }
    // [a] in the pattern stops pgrep from matching this very command line
    Process { id: pClicker; command: ["sh","-c","pgrep -f '[a]utoclicker.py' >/dev/null && echo 1 || echo 0"]
        stdout: SplitParser { onRead: l => hud.clickerOn = (l.trim() === "1") } }
    Process { id: pIdler; command: ["sh","-c","systemctl --user is-active steam-idler 2>/dev/null"]
        stdout: SplitParser { onRead: l => hud.idlerOn = (l.trim() === "active") } }

    function refresh() { pNight.running = true; pWifi.running = true; pBt.running = true; pBright.running = true; pClicker.running = true; pIdler.running = true }
    Timer { running: hud.visible; interval: 3000; repeat: true; triggeredOnStart: true; onTriggered: hud.refresh() }

    // media
    property var player: {
        var ps = Mpris.players ? Mpris.players.values : []
        for (var i = 0; i < ps.length; i++) if (ps[i].playbackState === MprisPlaybackState.Playing) return ps[i]
        return ps.length ? ps[0] : null
    }
    property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: hud.sink ? [hud.sink] : [] }

    // ── sliding card ──
    Rectangle {
        id: card
        width: parent.width - 16
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right; margins: 8 }
        radius: App.Theme.radius
        color: App.Theme.panel
        border.width: 1
        border.color: App.Theme.accentEdge

        // slide-in
        transform: Translate { id: tr; x: hud.visible ? 0 : 400 }
        Behavior on opacity { NumberAnimation { duration: App.Theme.anim } }
        states: State { when: hud.visible; PropertyChanges { target: tr; x: 0 } }

        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 16

            // header
            Column {
                spacing: 2
                Text { text: "◕▿◕  proto//green"; font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize; color: App.Theme.muted }
                Text {
                    text: Qt.formatDateTime(headClock.date, "HH:mm")
                    font.family: App.Theme.fontMono; font.pixelSize: 40; font.bold: true; color: App.Theme.fg
                }
                Text {
                    text: Qt.formatDateTime(headClock.date, "dddd, d MMMM")
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize; color: App.PowerProfile.accentBri
                }
                SystemClock { id: headClock; precision: SystemClock.Minutes }
            }

            // big cava
            Rectangle {
                width: parent.width; height: 70; radius: App.Theme.pillRadius
                color: App.Theme.surface; clip: true
                C.CavaBars {
                    anchors.centerIn: parent
                    levels: App.Cava.levels
                    maxHeight: 56
                }
            }

            // media card
            Rectangle {
                width: parent.width; height: 78; radius: App.Theme.pillRadius
                color: App.Theme.surface
                visible: hud.player !== null
                Column {
                    anchors { left: parent.left; right: ctrls.left; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 10 }
                    spacing: 3
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: hud.player ? (hud.player.trackTitle || "—") : ""
                        font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 1; font.bold: true; color: App.Theme.fg
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: hud.player ? (hud.player.trackArtist || "") : ""
                        font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize; color: App.Theme.muted
                    }
                }
                Row {
                    id: ctrls
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
                    spacing: 10
                    Repeater {
                        model: [{ g: "󰒮", a: "prev" }, { g: hud.player && hud.player.playbackState === MprisPlaybackState.Playing ? "󰏤" : "󰐊", a: "play" }, { g: "󰒭", a: "next" }]
                        Text {
                            required property var modelData
                            text: modelData.g
                            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 8; color: App.PowerProfile.accentBri
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!hud.player) return
                                    if (parent.modelData.a === "prev") hud.player.previous()
                                    else if (parent.modelData.a === "next") hud.player.next()
                                    else hud.player.togglePlaying()
                                }
                            }
                        }
                    }
                }
            }

            // toggles
            Flow {
                width: parent.width
                spacing: 10
                C.ToggleButton { glyph: "󰖔"; label: "night"; on: hud.nightOn
                    onClicked: { App.Compositor.exec(App.Compositor.nightOffCmd + " || " + App.Compositor.nightOnCmd); refreshT.restart() } }
                C.ToggleButton { glyph: "󰖩"; label: "wifi"; on: hud.wifiOn
                    onClicked: { App.Compositor.exec("nmcli radio wifi " + (hud.wifiOn ? "off" : "on")); refreshT.restart() } }
                C.ToggleButton { glyph: "󰂯"; label: "bt"; on: hud.btOn
                    onClicked: { App.Compositor.exec("bluetoothctl power " + (hud.btOn ? "off" : "on")); refreshT.restart() } }
                C.ToggleButton { glyph: "󰌾"; label: "lock"
                    onClicked: { App.Bus.hud = false; App.Compositor.lock() } }
                C.ToggleButton { glyph: "󰍽"; label: "clicker"; on: hud.clickerOn
                    onClicked: { App.Bus.hud = false; App.Compositor.exec("__HOME__/.config/hypr/scripts/autoclicker_gui.py") } }
                C.ToggleButton { glyph: "🎮"; label: "idler"; on: hud.idlerOn
                    onClicked: { App.Compositor.exec("systemctl --user " + (hud.idlerOn ? "stop" : "start") + " steam-idler"); refreshT.restart() } }
                C.ToggleButton { glyph: "󰏘"; label: "theme"; on: App.Bus.theme
                    onClicked: App.Bus.toggleTheme() }
                C.ToggleButton { glyph: "✛"; label: "xhair"; on: App.Bus.crosshair
                    onClicked: App.Bus.toggleCrosshair() }
            }
            Timer { id: refreshT; interval: 400; onTriggered: hud.refresh() }

            // sliders
            Column {
                width: parent.width
                spacing: 12
                C.VSlider {
                    width: parent.width; glyph: "󰕾"
                    value: hud.sink && hud.sink.audio ? hud.sink.audio.volume : 0
                    onMoved: v => { if (hud.sink && hud.sink.audio) hud.sink.audio.volume = v }
                }
                C.VSlider {
                    width: parent.width; glyph: "󰃟"
                    value: hud.bright
                    onMoved: v => { hud.bright = v; App.Compositor.exec("brightnessctl set " + Math.round(v*100) + "%") }
                }
            }

            // ── talk to NULL (assistant) ──
            Rectangle {
                width: parent.width; height: 46; radius: App.Theme.pillRadius
                color: App.Bus.assistant ? App.Theme.accentWash : App.Theme.surface2
                border.width: 1
                border.color: App.Bus.assistant ? App.PowerProfile.accent : App.Theme.hairline
                Behavior on color { ColorAnimation { duration: App.Theme.animF } }
                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    Text { text: "◕▿◕"; font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 4
                           font.bold: true; color: App.PowerProfile.accentBri; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "talk to Pip"; font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                           color: App.Theme.fg; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: { App.Bus.assistant = true; App.Bus.hud = false }
                }
            }

            Item { width: 1; height: 4 }

            // power row
            Row {
                spacing: 10
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: [{ g: "󰍃", c: "loginctl terminate-user $USER" }, { g: "󰒲", c: "systemctl suspend" }, { g: "󰜉", c: "systemctl reboot" }, { g: "󰐥", c: "systemctl poweroff" }]
                    Rectangle {
                        required property var modelData
                        width: 56; height: 40; radius: App.Theme.pillRadius
                        color: App.Theme.surface2
                        border.width: 1; border.color: App.Theme.hairline
                        Text { anchors.centerIn: parent; text: parent.modelData.g; font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 6; color: App.Theme.fg }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { App.Bus.hud = false; App.Compositor.exec(parent.modelData.c) } }
                    }
                }
            }
        }
    }
}
