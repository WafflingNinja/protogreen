import QtQuick
import Quickshell
import Quickshell.Io
import "../" as App

// Loop editor — fix a wallpaper whose seam jumps, without re-recording it.
//
// A recording made with --keep-raw leaves the near-lossless capture next to the mp4.
// This re-cuts THAT: recording takes over the screen for a minute, re-cutting is a few
// seconds and leaves the desktop alone, so you can iterate until the seam is clean.
//
// The two frames shown are the ones that actually meet when the video wraps — the
// first frame of the cut and the last. If they match, it loops invisibly. There is no
// video preview because judging a seam needs those two stills side by side, not
// playback.
Item {
    id: root

    property var wp: null                 // the wallpaper row from wpscan
    property real duration: 0
    property real trimStart: 0
    property real len: 0
    property real fade: 0.6
    property bool kept: false
    property bool busy: false
    property int  stamp: 0                // unique tag per probe → unique frame filenames
    property string inFile: ""
    property string outFile: ""

    signal closed()

    readonly property string scripts: "__HOME__/.config/hypr/scripts"

    onWpChanged: {
        if (!wp) return
        trimStart = 0
        len = App.ThemeState.wp.seconds
        probe()
    }

    // ── seam frames ──
    Process {
        id: seam
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text)
                    root.duration = d.duration
                    root.kept = d.kept
                    if (root.len <= 0 || root.len > d.duration) root.len = d.duration
                    // Fresh paths — this is what actually makes the images update.
                    root.inFile = d.inFile
                    root.outFile = d.outFile
                } catch (e) { /* keep previous bounds and frames */ }
            }
        }
    }
    function probe() {
        if (!wp) return
        stamp++
        seam.command = [scripts + "/wpseam.sh", "--id", wp.id,
                        "--trim-start", String(Math.round(trimStart)),
                        "--seconds", String(Math.round(len)),
                        "--tag", String(stamp)]
        seam.running = true
    }
    // Dragging a slider fires continuously; only probe once it settles.
    Timer { id: probeDebounce; interval: 220; onTriggered: root.probe() }

    Process {
        id: render
        onExited: { root.busy = false; root.probe() }
    }
    function rerender() {
        if (busy || !wp) return
        busy = true
        var w = App.ThemeState.wp
        render.command = [scripts + "/wpconvert.sh", "--reencode",
                          "--id", wp.id,
                          "--fps", String(w.fps),
                          "--seconds", String(Math.round(len)),
                          "--crf", String(w.crf),
                          "--codec", String(w.codec),
                          "--trim-start", String(Math.round(trimStart)),
                          "--fade", fade.toFixed(2),
                          "--set"]
        render.running = true
    }

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
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closed() }
        }
        Text {
            anchors { left: backBtn.right; leftMargin: 10; right: parent.right
                      verticalCenter: parent.verticalCenter }
            text: "loop editor" + (root.wp ? "  ·  " + root.wp.title : "")
            elide: Text.ElideRight
            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 1
            font.bold: true
            color: App.PowerProfile.accentBri
        }
    }

    Column {
        anchors { top: head.bottom; topMargin: 8; left: parent.left; right: parent.right }
        spacing: 10

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.kept
                  ? "These two frames are what meet when the video wraps. Match them and the loop is invisible."
                  : "No kept capture for this wallpaper — re-record it with the ⟳ badge first, then it can be re-cut here without recording again."
            font.family: App.Theme.font
            font.pixelSize: App.Theme.fontSize - 2
            color: root.kept ? App.Theme.muted : App.Theme.amber
        }

        // seam frames, side by side
        Row {
            width: parent.width
            spacing: 8
            Repeater {
                model: [{ f: root.inFile, n: "first frame" },
                        { f: root.outFile, n: "last frame" }]
                Column {
                    required property var modelData
                    width: (parent.width - 8) / 2
                    spacing: 3
                    Rectangle {
                        width: parent.width
                        height: Math.round(width * 0.5625)
                        radius: App.Theme.pillRadius
                        color: App.Theme.surface
                        border.width: 1; border.color: App.Theme.hairline
                        clip: true
                        Image {
                            anchors.fill: parent
                            // wpseam.sh writes a NEW filename each probe, so the source
                            // URL genuinely changes and Qt reloads it.
                            source: parent.parent.modelData.f ? "file://" + parent.parent.modelData.f : ""
                            fillMode: Image.PreserveAspectFit
                            cache: false
                            asynchronous: true
                            sourceSize.width: 360
                        }
                    }
                    Text {
                        text: parent.modelData.n
                        font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 3
                        color: App.Theme.muted
                    }
                }
            }
        }

        LabeledSlider {
            width: parent.width
            label: "start"; from: 0; to: Math.max(1, root.duration - 2); suffix: "s"
            value: root.trimStart
            onMoved: v => { root.trimStart = v; probeDebounce.restart() }
        }
        LabeledSlider {
            width: parent.width
            label: "length"; from: 3
            to: Math.max(4, root.duration - root.trimStart); suffix: "s"
            value: root.len
            onMoved: v => { root.len = v; probeDebounce.restart() }
        }
        LabeledSlider {
            width: parent.width
            label: "crossfade"; from: 0; to: 3; decimals: 2; suffix: "s"
            value: root.fade
            onMoved: v => root.fade = v
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "crossfade dissolves the tail back over the head, so the result is "
                  + Math.max(0, root.len - root.fade).toFixed(1)
                  + "s long. 0 = a hard cut."
            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 3
            color: App.Theme.muted
        }

        Rectangle {
            width: parent.width; height: 38
            radius: App.Theme.pillRadius
            color: root.kept ? App.PowerProfile.accent : App.Theme.surface2
            opacity: root.busy ? 0.6 : 1.0
            Text {
                anchors.centerIn: parent
                text: root.busy ? "re-cutting…" : "re-cut and apply"
                font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1
                font.bold: true
                color: root.kept ? App.Theme.bg : App.Theme.muted
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: root.kept && !root.busy
                onClicked: root.rerender()
            }
        }
    }
}
