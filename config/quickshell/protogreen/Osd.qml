import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Services.Pipewire
import "." as App

// Protogen HUD on-screen-display for volume + brightness changes.
PanelWindow {
    id: osd
    required property var modelData
    screen: modelData

    anchors { bottom: true }
    margins { bottom: 140 }
    implicitWidth: 320
    implicitHeight: 84
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.namespace: "protogreen-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: false

    property bool ready: false
    property string kind: "vol"      // vol | bright
    property real value: 0
    property bool muted: false

    Timer { interval: 1200; running: true; onTriggered: osd.ready = true }   // ignore startup binds
    Timer { id: hideT; interval: 1600; onTriggered: osd.visible = false }

    function flash(k, v, m) {
        console.log("OSDDBG flash kind=" + k + " val=" + v + " muted=" + m + " ready=" + ready
                    + " sink=" + (osd.sink ? osd.sink.name : "null") + " t=" + Date.now())
        if (!ready) return
        if (App.Bus.capture) return          // never pop over a wallpaper recording
        if (k === "vol" && !volArmed) {
            console.log("OSDDBG suppressed: sink swap settling"); sinkSettle.restart(); return
        }
        kind = k; value = Math.max(0, Math.min(1, v)); muted = m === true
        visible = true; hideT.restart()
    }

    // ── volume source (Pipewire) ──
    property var sink: Pipewire.defaultAudioSink
    // A new default sink (BT headset connecting, headphones plugged) pushes its stored
    // volume the moment it binds, which fired the OSD with a number nobody asked for.
    // Arm only after the volume has been quiet for 900ms: every suppressed push
    // restarts the timer, so a sink that takes seconds to bind (BT headset) stays
    // muzzled the whole time instead of only for the first 900ms.
    property bool volArmed: false
    onSinkChanged: { volArmed = false; sinkSettle.restart() }
    Timer { id: sinkSettle; interval: 900; running: true; onTriggered: osd.volArmed = true }
    PwObjectTracker { objects: osd.sink ? [osd.sink] : [] }
    Connections {
        target: osd.sink && osd.sink.audio ? osd.sink.audio : null
        function onVolumeChanged() { osd.flash("vol", osd.sink.audio.volume, osd.sink.audio.muted) }
        function onMutedChanged()  { osd.flash("vol", osd.sink.audio.volume, osd.sink.audio.muted) }
    }

    // ── brightness source (sysfs watch) ──
    property int bmax: 1
    FileView {
        path: "/sys/class/backlight/intel_backlight/max_brightness"
        onLoaded: { var v = parseInt(text()); if (v > 0) osd.bmax = v }
    }
    FileView {
        path: "/sys/class/backlight/intel_backlight/brightness"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { var v = parseInt(text()); if (osd.bmax > 0) osd.flash("bright", v / osd.bmax, false) }
    }

    // ── visor readout ──
    Rectangle {
        anchors.fill: parent
        radius: App.Theme.radius
        color: App.Theme.panelDeep
        border.width: 1
        border.color: Qt.rgba(App.PowerProfile.accent.r, App.PowerProfile.accent.g, App.PowerProfile.accent.b, 0.4)

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Row {
                spacing: 12
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: osd.kind === "bright" ? "󰃟"
                          : (osd.muted ? "󰝟" : (osd.value < 0.34 ? "󰕿" : (osd.value < 0.67 ? "󰖀" : "󰕾")))
                    font.family: App.Theme.font; font.pixelSize: 26
                    color: App.PowerProfile.accentBri
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: osd.kind === "bright" ? "brightness" : (osd.muted ? "muted" : "volume")
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                    color: App.Theme.muted
                }
                Item { width: osd.width - 200; height: 1 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(osd.value * 100) + "%"
                    font.family: App.Theme.fontMono; font.pixelSize: App.Theme.fontSize; font.bold: true
                    color: App.Theme.fg
                }
            }

            // level bar
            Rectangle {
                width: parent.width; height: 8; radius: 4
                color: App.Theme.surface2
                Rectangle {
                    height: parent.height; radius: 4
                    width: parent.width * (osd.muted && osd.kind === "vol" ? 0 : osd.value)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: App.PowerProfile.accent }
                        GradientStop { position: 1.0; color: App.Theme.teal }
                    }
                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                }
            }
        }
    }
}
