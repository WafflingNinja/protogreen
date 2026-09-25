pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "." as App

// Active power profile (power-profiles-daemon) + the accent the shell paints with.
//
// The THEME owns the colour; the profile only nudges it. Previously each profile
// hardcoded its own green/lime/teal, which meant picking a purple theme and then
// switching to performance threw the theme away and painted the bar lime. Now
// performance shifts the theme accent warmer and brighter, power-saver shifts it
// cooler and slightly darker, and balanced leaves it exactly as the theme set it —
// so the power cue survives while the theme stays recognisably itself.
Singleton {
    id: root
    property string profile: "balanced"   // performance | balanced | power-saver

    // hue shift (turns), lightness shift. Small on purpose: this is a status hint,
    // not a second theme.
    readonly property var shifts: ({
        "performance": { h: -0.045, l:  0.07 },
        "balanced":    { h:  0.0,   l:  0.0  },
        "power-saver": { h:  0.050, l: -0.04 }
    })
    readonly property var sh: shifts[profile] ? shifts[profile] : shifts["balanced"]

    function _tint(c, dh, dl) {
        var h = c.hslHue < 0 ? 0 : c.hslHue
        return Qt.hsla(((h + dh) % 1 + 1) % 1,
                       Math.max(0, Math.min(1, c.hslSaturation)),
                       Math.max(0, Math.min(1, c.hslLightness + dl)), 1)
    }

    readonly property color accent:    _tint(App.Theme.accent,  sh.h, sh.l)
    readonly property color accentBri: _tint(App.Theme.bright,  sh.h, sh.l)
    readonly property color accent2:   _tint(App.Theme.accent2, sh.h, sh.l)

    Process {
        id: get
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser { onRead: l => { var p = l.trim(); if (p) root.profile = p } }
    }
    // powerprofilesctl is a python script — every poll is a full interpreter spawn, and
    // at 4s that was ~21k of them a day to read a value that changes a few times a day.
    // Panel picks update the pill instantly (applyManual/auto set it directly); this poll
    // only exists to catch power-watch.sh flipping AC/battery behind our back, so the pill
    // can lag that by up to 15s. ponytail: raise further only if you also watch AC state.
    Timer { running: true; interval: 15000; repeat: true; triggeredOnStart: true; onTriggered: get.running = true }

    // manual pick: set profile AND drop the override flag so power-watch.sh stops
    // auto-switching (otherwise its AC=balanced/battery=power-saver wipes the pick).
    function applyManual(p) {
        setProc.command = ["sh", "-c", "powerprofilesctl set " + p + " && echo " + p + " > /tmp/power-profile.manual"]
        setProc.running = true
        profile = p
    }
    function cycle() {
        var order = ["power-saver", "balanced", "performance"]
        var i = order.indexOf(profile)
        applyManual(order[(i + 1) % order.length])
    }
    // back to automatic: clear override, apply the power-source default now.
    function auto() {
        setProc.command = ["sh", "-c",
            "rm -f /tmp/power-profile.manual; " +
            "if [ \"$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1)\" = Discharging ]; " +
            "then powerprofilesctl set power-saver; else powerprofilesctl set balanced; fi"]
        setProc.running = true
        get.running = true
    }
    Process { id: setProc }
}
