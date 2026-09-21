import QtQuick
import "../" as App

// One workspace rendered as a protogen visor "eye".
//  active   -> bright open lens, cyan pupil, halo
//  occupied -> dim green lens
//  empty    -> faint outline dot
// Eyes blink on a random timer and do a happy squint when focused.
Item {
    id: eye
    property int wsId: 1
    property bool active: false
    property bool occupied: false

    property real eyeOpen: 1.0   // 1 = fully open, 0 = closed (blink)
    property real squish: 0.0    // happy-squint amount when activated

    implicitWidth: active ? 30 : (occupied ? 18 : 12)
    implicitHeight: App.Theme.barHeight
    Behavior on implicitWidth { NumberAnimation { duration: App.Theme.anim; easing.type: Easing.OutBack } }

    // ── halo (fake glow, no GraphicsEffects dependency) ──
    Rectangle {
        anchors.centerIn: lens
        width: lens.width + 12
        height: lens.height + 12
        radius: height / 2
        color: App.PowerProfile.accent
        opacity: eye.active ? 0.30 : 0.0
        Behavior on opacity { NumberAnimation { duration: App.Theme.anim } }
    }

    // ── lens ──
    Rectangle {
        id: lens
        anchors.centerIn: parent
        width: eye.active ? 26 : (eye.occupied ? 14 : 8)
        height: (eye.active ? 16 : (eye.occupied ? 12 : 8))
                * eye.eyeOpen * (1.0 - eye.squish * 0.55)
        radius: height / 2
        color: eye.active ? App.PowerProfile.accentBri
                          : (eye.occupied ? App.PowerProfile.accent : "transparent")
        border.width: eye.occupied || eye.active ? 0 : 1.5
        border.color: App.Theme.muted
        antialiasing: true
        Behavior on width  { NumberAnimation { duration: App.Theme.anim; easing.type: Easing.OutBack } }

        // pupil / scanline glint
        Rectangle {
            anchors.centerIn: parent
            visible: eye.active && eye.eyeOpen > 0.4 && eye.squish < 0.5
            width: 6; height: parent.height * 0.55
            radius: 2
            color: App.Theme.teal
            opacity: 0.9
        }
    }

    // click -> jump to workspace
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: App.Compositor.gotoWorkspace(eye.wsId)
    }

    // ── blink ──
    Timer {
        interval: 2500 + Math.random() * 4500
        running: true
        repeat: true
        onTriggered: { blink.restart(); interval = 2500 + Math.random() * 4500 }
    }
    SequentialAnimation {
        id: blink
        NumberAnimation { target: eye; property: "eyeOpen"; to: 0.08; duration: 70 }
        NumberAnimation { target: eye; property: "eyeOpen"; to: 1.0;  duration: 130; easing.type: Easing.OutQuad }
    }

    // ── happy squint on activation ──
    onActiveChanged: if (active) squintAnim.restart()
    SequentialAnimation {
        id: squintAnim
        NumberAnimation { target: eye; property: "squish"; to: 0.8; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: eye; property: "squish"; to: 0.0; duration: 220; easing.type: Easing.OutBack }
    }
}
