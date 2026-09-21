pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    readonly property int bars: 12
    // normalised 0..1 levels, one per bar
    property var levels: { var a = []; for (var i = 0; i < bars; i++) a.push(0); return a; }
    // peak of all bars (for the "is music playing" / pulse intensity)
    property real peak: 0

    // only run cava while something is actually playing — silent bars cost nothing
    property bool anyPlaying: {
        var ps = Mpris.players ? Mpris.players.values : []
        for (var i = 0; i < ps.length; i++)
            if (ps[i].playbackState === MprisPlaybackState.Playing) return true
        return false
    }
    function _zero() { var a = []; for (var i = 0; i < bars; i++) a.push(0); levels = a; peak = 0 }
    onAnyPlayingChanged: {
        if (anyPlaying) proc.running = true
        else { proc.running = false; _zero() }
    }

    Process {
        id: proc
        running: false                 // started on demand when audio plays
        command: ["cava", "-p", Qt.resolvedUrl("services/cava.conf").toString().replace("file://", "")]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (!line) return
                var parts = line.split(";")
                var out = []
                var mx = 0
                for (var i = 0; i < root.bars; i++) {
                    var v = parseInt(parts[i])
                    if (isNaN(v)) v = 0
                    var n = Math.min(1, v / 100)
                    out.push(n)
                    if (n > mx) mx = n
                }
                root.levels = out
                root.peak = mx
            }
        }

        // restart cava if it dies mid-playback (e.g. pulse hiccup)
        onExited: (code, status) => { if (root.anyPlaying) restart.start() }
    }

    Timer {
        id: restart
        interval: 1500
        repeat: false
        onTriggered: if (root.anyPlaying) proc.running = true
    }
}
