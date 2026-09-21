import QtQuick
import Quickshell
import Quickshell.Io
import "../" as App

// Wallpaper Engine library as a thumbnail grid.
//
// Two very different costs hide behind one click, so the UI has to be honest about
// which is which:
//   video wallpapers already ship a playable file → setting one is instant.
//   scene wallpapers must be recorded first (wpconvert.sh, ~1-2 min) → the tile
//   shows that it will convert, and says so again while it runs.
// Once converted, the mp4 is cached under ~/.config/protogreen/wallpapers and the
// tile behaves like a video one forever after.
Item {
    id: root

    property string filter: "scene"        // scene | video | all
    property var items: []
    property bool loading: true
    property string busyId: ""
    property string activePath: ""
    signal editLoop(var wp)

    readonly property string scripts: "__HOME__/.config/hypr/scripts"

    readonly property var shown: {
        var out = []
        for (var i = 0; i < items.length; ++i) {
            var w = items[i]
            if (filter === "all" || w.type === filter) out.push(w)
        }
        return out
    }

    Process {
        id: scanner
        command: ["python3", root.scripts + "/wpscan.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.items = JSON.parse(this.text) } catch (e) { root.items = [] }
                root.loading = false
            }
        }
    }
    function refresh() { root.loading = true; scanner.running = true }

    // Reads which mp4 the desktop is currently pointed at, so the active tile can
    // be marked. Missing file is normal (means "still on the built-in default").
    Process {
        id: pointerRead
        command: ["cat", "__HOME__/.config/protogreen/wallpaper.path"]
        stdout: StdioCollector { onStreamFinished: root.activePath = this.text.trim() }
    }

    // Path is passed as an argument, never interpolated into the shell string.
    Process { id: setter; onExited: pointerRead.running = true }
    function setWallpaper(path) {
        setter.command = ["sh", "-c",
            "mkdir -p ~/.config/protogreen && printf '%s\\n' \"$1\" > ~/.config/protogreen/wallpaper.path",
            "sh", path]
        setter.running = true
    }

    Process {
        id: converter
        onExited: {
            root.busyId = ""
            root.refresh()
            pointerRead.running = true
        }
    }
    function convert(w) {
        if (busyId !== "") return                  // one capture at a time — it owns the screen
        busyId = w.id
        var wp = App.ThemeState.wp
        // --keep-raw so the loop editor can re-cut this later without taking the
        // screen over for another full recording.
        converter.command = [root.scripts + "/wpconvert.sh",
                             "--id", w.id,
                             "--fps", String(wp.fps),
                             "--seconds", String(wp.seconds),
                             "--crf", String(wp.crf),
                             "--codec", String(wp.codec),
                             "--keep-raw",
                             "--set"]
        converter.running = true
    }

    function activate(w) {
        if (w.mp4 && w.mp4.length > 0) { setWallpaper(w.mp4); return }   // cached conversion
        if (w.type === "video" && w.src && w.src.length > 0) { setWallpaper(w.src); return }
        convert(w)
    }

    // Force a fresh recording even when a cached mp4 already exists — otherwise
    // there is no way to REPLACE a conversion after changing the fps/length/quality
    // sliders, because activate() would just re-point at the old file forever.
    // ffmpeg runs with -y, so the cached mp4 is overwritten in place.
    function reconvert(w) {
        if (w.type === "video") return       // video types are played directly, nothing to record
        convert(w)
    }

    Process { id: chat }
    function openChat(w) {
        // Hands the wallpaper's own folder to Claude Code, with the skill that
        // documents the Wallpaper Engine scene format and this conversion pipeline.
        chat.command = ["kitty", "--directory", w.dir, "sh", "-c",
                        "claude 'Read the wallpaper-engine skill, then help me with this wallpaper: " +
                        "id " + w.id + ", type " + w.type + ". The folder is the current directory.'"]
        chat.running = true
    }

    Component.onCompleted: { refresh(); pointerRead.running = true }

    // ── filter chips ──
    Row {
        id: chips
        spacing: 6
        Repeater {
            model: [{ k: "scene", n: "scene" }, { k: "video", n: "video" }, { k: "all", n: "all" }]
            Rectangle {
                required property var modelData
                height: 22
                width: chipText.implicitWidth + 18
                radius: App.Theme.pillRadius
                color: root.filter === modelData.k ? App.PowerProfile.accent : App.Theme.surface2
                border.width: 1
                border.color: root.filter === modelData.k ? App.PowerProfile.accentBri : App.Theme.hairline
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: parent.modelData.n
                    font.family: App.Theme.font
                    font.pixelSize: App.Theme.fontSize - 1
                    color: root.filter === parent.modelData.k ? App.Theme.bg : App.Theme.fg
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: root.filter = parent.modelData.k
                }
            }
        }
    }

    Text {
        anchors { right: parent.right; verticalCenter: chips.verticalCenter }
        text: root.loading ? "scanning…" : root.shown.length + " wallpapers"
        font.family: App.Theme.font
        font.pixelSize: App.Theme.fontSize - 1
        color: App.Theme.muted
    }

    GridView {
        id: grid
        anchors { top: chips.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        cellWidth: Math.floor(width / 3)
        cellHeight: Math.round(cellWidth * 0.62)
        model: root.shown

        delegate: Item {
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors { fill: parent; margins: 3 }
                radius: App.Theme.pillRadius
                color: App.Theme.surface
                border.width: root.activePath !== "" &&
                              (root.activePath === modelData.mp4 || root.activePath === modelData.src) ? 2 : 1
                border.color: root.activePath !== "" &&
                              (root.activePath === modelData.mp4 || root.activePath === modelData.src)
                              ? App.PowerProfile.accentBri : App.Theme.hairline
                clip: true

                Image {
                    anchors.fill: parent
                    source: modelData.preview ? "file://" + modelData.preview : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // The library is ~100 animated gifs; decoding them all at full
                    // size would cost more memory than the whole bar. Cap the
                    // decode size to roughly what a tile actually shows.
                    sourceSize.width: 320
                    smooth: true
                }

                // legibility scrim behind the title
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 30
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.80) }
                    }
                }
                Text {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 5 }
                    text: modelData.title
                    elide: Text.ElideRight
                    font.family: App.Theme.font
                    font.pixelSize: App.Theme.fontSize - 2
                    color: "#ffffff"
                }

                // Corner badge: ⚙ = scene, needs recording first · ⟳ = already
                // recorded, click this to RE-record it (e.g. after changing the
                // fps/length/quality sliders). Plain click would only replay the
                // cached file, which is not obvious otherwise.
                Rectangle {
                    id: badge
                    visible: modelData.type !== "video"
                    anchors { top: parent.top; right: parent.right; margins: 4 }
                    width: 22; height: 18; radius: 4
                    color: Qt.rgba(0, 0, 0, 0.6)
                    Text {
                        anchors.centerIn: parent
                        text: modelData.mp4 ? "⟳" : "⚙"
                        font.pixelSize: App.Theme.fontSize - 2
                        color: App.PowerProfile.accentBri
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -3
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.reconvert(modelData)
                    }
                }

                // busy overlay while this one is being recorded
                Rectangle {
                    visible: root.busyId === modelData.id
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.72)
                    Text {
                        anchors.centerIn: parent
                        text: "recording…"
                        font.family: App.Theme.font
                        font.pixelSize: App.Theme.fontSize - 1
                        color: App.PowerProfile.accentBri
                    }
                }

                // ✂ opens the loop editor — only useful once something is recorded.
                Rectangle {
                    visible: modelData.type !== "video" && modelData.mp4
                    anchors { top: parent.top; right: badge.left; rightMargin: 3; topMargin: 4 }
                    width: 22; height: 18; radius: 4
                    color: Qt.rgba(0, 0, 0, 0.6)
                    Text {
                        anchors.centerIn: parent; text: "✂"
                        font.pixelSize: App.Theme.fontSize - 3
                        color: App.PowerProfile.accentBri
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -3
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.editLoop(modelData)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) root.openChat(modelData)
                        else root.activate(modelData)
                    }
                }
            }
        }
    }
}
