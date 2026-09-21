import QtQuick
import Quickshell.Wayland
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import "../" as App

// Protogen mascot that reacts to machine state. Click = launcher.
Item {
    id: root
    implicitWidth: face.implicitWidth + (note.visible ? note.implicitWidth + 4 : 0)
    implicitHeight: App.Theme.barHeight

    property var bat: UPower.displayDevice
    property bool lowBatt: bat && bat.isLaptopBattery
                           && bat.percentage * 100 <= 15
                           && bat.state === UPowerDeviceState.Discharging
    property bool hot: App.Sys.cpu >= 85
    property bool music: {
        var ps = Mpris.players ? Mpris.players.values : []
        for (var i = 0; i < ps.length; i++)
            if (ps[i].playbackState === MprisPlaybackState.Playing) return true
        return false
    }

    // window-aware base mood: the visor notices what you're doing
    property string appId: (ToplevelManager.activeToplevel && ToplevelManager.activeToplevel.appId)
                           ? ToplevelManager.activeToplevel.appId.toLowerCase() : ""
    property string appMood: {
        if (/sober|roblox|steam|gamescope|lutris|minecraft|game/.test(appId)) return "⊙▿⊙"   // locked in
        if (/kitty|alacritty|foot|wezterm|term|code|kate|nvim|jetbrains/.test(appId)) return "◑▿◑"  // working
        return "◕▿◕"                                                                          // chill / default
    }

    // mood (priority: asleep > low batt > hot > music > window-aware)
    property bool asleep: App.Bus.asleep
    property string mood: asleep ? "=ᴗ=" : (lowBatt ? "◔﹏◔" : (hot ? ">︿<" : (music ? "◕ᴗ◕" : appMood)))
    property color moodColor: asleep ? App.Theme.muted
                              : (lowBatt ? App.Theme.danger
                              : (hot ? App.Theme.amber : App.PowerProfile.accentBri))

    Text {
        id: face
        anchors.verticalCenter: parent.verticalCenter
        text: root.mood
        font.family: App.Theme.font
        font.pixelSize: App.Theme.fontSize + 3
        font.bold: true
        color: root.moodColor
        Behavior on color { ColorAnimation { duration: 300 } }

        transform: Scale { id: sc; origin.x: face.width / 2; origin.y: face.height / 2; yScale: 1 }
    }

    // bouncing note when music plays
    Text {
        id: note
        visible: root.music
        anchors { left: face.right; leftMargin: 4; verticalCenter: parent.verticalCenter }
        text: "󰎈"
        font.family: App.Theme.font
        font.pixelSize: App.Theme.fontSize
        color: App.PowerProfile.accent
        SequentialAnimation on y {
            running: root.music; loops: Animation.Infinite
            NumberAnimation { to: -3; duration: 380; easing.type: Easing.OutSine }
            NumberAnimation { to: 2;  duration: 380; easing.type: Easing.InSine }
        }
    }

    // floating "z" while the visor dozes
    Text {
        visible: root.asleep
        anchors { left: face.right; leftMargin: 1; verticalCenter: face.verticalCenter; verticalCenterOffset: -7 }
        text: "z"
        font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 3
        color: App.Theme.muted
        SequentialAnimation on opacity {
            running: root.asleep; loops: Animation.Infinite
            NumberAnimation { from: 0.2; to: 0.9; duration: 1100; easing.type: Easing.OutSine }
            NumberAnimation { from: 0.9; to: 0.2; duration: 1100; easing.type: Easing.InSine }
        }
    }

    // periodic blink (squish whole face) — paused while asleep
    Timer {
        interval: 3000 + Math.random() * 4000
        running: !root.asleep; repeat: true
        onTriggered: { blink.restart(); interval = 3000 + Math.random() * 4000 }
    }
    SequentialAnimation {
        id: blink
        NumberAnimation { target: sc; property: "yScale"; to: 0.1; duration: 70 }
        NumberAnimation { target: sc; property: "yScale"; to: 1.0; duration: 130; easing.type: Easing.OutQuad }
    }
    // extra excited wiggle when music starts
    onMusicChanged: if (music) { blink.restart() }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: App.Compositor.exec("rofi -show drun")
    }
}
