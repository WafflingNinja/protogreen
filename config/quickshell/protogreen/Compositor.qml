pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.I3

// Compositor abstraction so the visor runs on BOTH Sway (i3 IPC) and Hyprland.
// Detection is by SWAYSOCK; everything compositor-specific lives here and nowhere else.
// Gotchas baked in (verified 2026-07-27):
//   - sway workspace `id` is an INTERNAL handle (4, 7, …); the visible number is `number`.
//     Hyprland's `id` IS the visible number. wsOccupied/focusedWs normalise to the visible one.
//   - the I3 module starts with an EMPTY workspace list — refreshWorkspaces() is required.
//   - `exec X` is identical syntax on both, so exec() needs no branching.
Singleton {
    id: root

    readonly property bool sway: {
        var s = Quickshell.env("SWAYSOCK")
        return s !== null && s !== undefined && s !== ""
    }

    // per-compositor tools (hyprlock/hyprsunset are Hyprland-only)
    readonly property string lockCmd:     sway ? "swaylock -f -c 0d1117" : "hyprlock"
    readonly property string nightOnCmd:  sway ? "gammastep -O 4000"     : "hyprsunset -t 4000"
    readonly property string nightOffCmd: sway ? "pkill gammastep"       : "pkill hyprsunset"
    readonly property string nightProc:   sway ? "gammastep"             : "hyprsunset"

    Component.onCompleted: if (sway) I3.refreshWorkspaces()

    // raw compositor command
    function dispatch(cmd) { if (sway) I3.dispatch(cmd); else Hyprland.dispatch(cmd) }
    // run a program (same syntax both sides)
    function exec(cmd) { dispatch("exec " + cmd) }
    function lock() { exec(lockCmd) }
    function gotoWorkspace(n) { dispatch(sway ? ("workspace number " + n) : ("workspace " + n)) }

    // visible number of the focused workspace
    readonly property int focusedWs: sway
        ? (I3.focusedWorkspace ? I3.focusedWorkspace.number : 1)
        : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1)

    // visible numbers of all live workspaces
    readonly property var occupied: {
        var out = []
        var src = sway ? (I3.workspaces ? I3.workspaces.values : [])
                       : (Hyprland.workspaces ? Hyprland.workspaces.values : [])
        for (var i = 0; i < src.length; i++)
            out.push(sway ? src[i].number : src[i].id)
        return out
    }
    function wsOccupied(n) { return occupied.indexOf(n) !== -1 }
}
