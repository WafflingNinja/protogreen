pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Centralised system stats (one sysinfo.sh process, shared by SysInfo pill + MoodFace).
Singleton {
    id: root
    property int cpu: 0
    property int ctemp: 0
    property int mem: 0
    property int gpu: 0
    property int gtemp: 0

    Process {
        running: true
        command: ["bash", Qt.resolvedUrl("services/sysinfo.sh").toString().replace("file://", "")]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                var p = line.split(";")
                if (p.length < 5) return
                root.cpu = parseInt(p[0]) || 0
                root.ctemp = parseInt(p[1]) || 0
                root.mem = parseInt(p[2]) || 0
                root.gpu = parseInt(p[3]) || 0
                root.gtemp = parseInt(p[4]) || 0
            }
        }
    }
}
