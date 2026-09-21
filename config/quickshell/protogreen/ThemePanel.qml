import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "." as App
import "components" as C

// The theme panel — SUPER+D → theme, or `qs -c protogreen ipc call theme toggle`.
//
// Everything above the APPLY row edits ThemeState.pending only, which is why the
// visor retints as you drag but the rest of the desktop does not: rewriting 15
// config files per drag frame would be unusable. APPLY commits pending to disk and
// runs the heavy pass; REVERT throws the edits away.
PanelWindow {
    id: panel
    required property var modelData
    screen: modelData

    readonly property bool open: App.Bus.theme

    anchors { top: true; bottom: true; left: true }
    implicitWidth: 430
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "protogreen-theme"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"

    // Mapped exactly while open. The slide-IN still animates (the sheet's x binding
    // runs once the window is up); the slide-OUT is skipped on purpose, because
    // every way of keeping the window alive to animate it out either deadlocks on
    // the unmapped window's zero geometry or needs a flag that fights this binding.
    // An instant close is not worth that complexity.
    visible: open && !App.Bus.capture

    // Which gradient stop the wheel is currently editing.
    property bool editingB: false
    property real wheelLightness: 0.60
    // Font picking gets the whole sheet — see FontMenu.qml for why it can't be a row.
    property bool fontView: false
    // Loop editor, likewise: it needs room for two seam frames side by side.
    property bool loopView: false
    property var  loopWp: null
    readonly property bool subView: fontView || loopView
    onOpenChanged: if (!open) { fontView = false; loopView = false }

    Rectangle {
        id: sheet
        width: parent.width - 16
        height: parent.height - 16
        anchors.verticalCenter: parent.verticalCenter
        x: panel.open ? 8 : -width - 20
        radius: App.Theme.radius
        // Near-opaque on purpose. Theme.panel's 0.86 alpha is tuned for the bar,
        // which is a thin strip; this sheet is full height, and with blur disabled
        // (the default here — it re-renders over the animated wallpaper every frame)
        // the desktop reads straight through it and the controls become unreadable.
        color: Qt.rgba(App.Theme.bg.r, App.Theme.bg.g, App.Theme.bg.b, 0.985)
        border.width: 1
        border.color: App.PowerProfile.accent

        Behavior on x {
            NumberAnimation { duration: App.Theme.anim; easing.type: Easing.OutExpo }
        }

        // Sub-views take over the sheet — the font list needs full height, and the
        // loop editor needs room for two seam frames side by side.
        // Both sub-views scan the system on Component.onCompleted (fontscan.py walks
        // 817 font families, wpscan.py the whole wallpaper library), so building them
        // eagerly cost ~50 MB of resident memory before the panel had ever been
        // opened. Loaded on demand instead — the sheet itself stays eager, so the
        // slide-in animation is unchanged.
        Loader {
            anchors { fill: parent; margins: 14; bottomMargin: 58 }
            active: panel.fontView
            sourceComponent: C.FontMenu {
                onClosed: panel.fontView = false
            }
        }

        Loader {
            anchors { fill: parent; margins: 14; bottomMargin: 58 }
            active: panel.loopView
            sourceComponent: C.LoopEditor {
                wp: panel.loopWp
                onClosed: panel.loopView = false
            }
        }

        Flickable {
            id: flick
            visible: !panel.subView
            // bottomMargin clears the pinned apply/revert row, so the last controls
            // can actually be scrolled to instead of sitting underneath it.
            anchors { fill: parent; margins: 14; bottomMargin: 58 }
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: flick.width
                spacing: 12

                // ── header ──
                Item {
                    width: parent.width; height: 26
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "◕▿◕  theme"
                        font.family: App.Theme.font
                        font.pixelSize: App.Theme.fontSize + 2
                        font.bold: true
                        color: App.PowerProfile.accentBri
                    }
                    Text {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: App.ThemeState.dirty ? "● unsaved" : App.ThemeState.themeName
                        font.family: App.Theme.font
                        font.pixelSize: App.Theme.fontSize - 1
                        color: App.ThemeState.dirty ? App.Theme.amber : App.Theme.muted
                    }
                }

                // ── colour wheel + stops ──
                Row {
                    width: parent.width
                    spacing: 12

                    C.ColorWheel {
                        id: wheel
                        width: 170; height: 170
                        lightness: panel.wheelLightness
                        value: panel.editingB ? App.ThemeState.b : App.ThemeState.a
                        onPicked: c => {
                            var hx = c.toString().substring(0, 7)
                            if (panel.editingB) App.ThemeState.setStops(App.ThemeState.a, hx)
                            else                App.ThemeState.setStops(hx, App.ThemeState.b)
                        }
                    }

                    Column {
                        width: parent.width - 170 - 12
                        spacing: 8

                        // A / B stop selector
                        Repeater {
                            model: [{ k: false, n: "A" }, { k: true, n: "B" }]
                            Rectangle {
                                required property var modelData
                                width: parent.width; height: 30
                                radius: App.Theme.pillRadius
                                color: panel.editingB === modelData.k ? App.Theme.surface2 : "transparent"
                                border.width: 1
                                border.color: panel.editingB === modelData.k
                                              ? App.PowerProfile.accent : App.Theme.hairline
                                Row {
                                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                    spacing: 8
                                    Rectangle {
                                        width: 18; height: 18; radius: 5
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: parent.parent.modelData.k ? App.ThemeState.b : App.ThemeState.a
                                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.2)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.parent.modelData.n + "  " +
                                              (parent.parent.modelData.k ? App.ThemeState.b : App.ThemeState.a)
                                        font.family: App.Theme.font
                                        font.pixelSize: App.Theme.fontSize - 1
                                        color: App.Theme.fg
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.editingB = parent.modelData.k
                                }
                            }
                        }

                        C.LabeledSlider {
                            width: parent.width
                            label: "light"; from: 0.15; to: 0.90; decimals: 2
                            value: panel.wheelLightness
                            onMoved: v => {
                                panel.wheelLightness = v
                                var c = Qt.hsla(wheel.value.hslHue < 0 ? 0 : wheel.value.hslHue,
                                                wheel.value.hslSaturation, v, 1)
                                var hx = c.toString().substring(0, 7)
                                if (panel.editingB) App.ThemeState.setStops(App.ThemeState.a, hx)
                                else                App.ThemeState.setStops(hx, App.ThemeState.b)
                            }
                        }

                        C.LabeledSlider {
                            width: parent.width
                            label: "angle"; from: 0; to: 360; suffix: "°"
                            value: App.ThemeState.angle
                            onMoved: v => App.ThemeState.setKey("angle", Math.round(v))
                        }
                    }
                }

                // gradient strip
                Rectangle {
                    width: parent.width; height: 26; radius: App.Theme.pillRadius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: App.Theme.bright }
                        GradientStop { position: 0.5; color: App.Theme.accent }
                        GradientStop { position: 1.0; color: App.Theme.accent2 }
                    }
                }

                // dark / light
                Row {
                    width: parent.width; spacing: 8
                    Repeater {
                        model: [{ d: true, n: "dark" }, { d: false, n: "light" }]
                        Rectangle {
                            required property var modelData
                            width: (col.width - 8) / 2; height: 28
                            radius: App.Theme.pillRadius
                            color: App.ThemeState.dark === modelData.d ? App.PowerProfile.accent : App.Theme.surface2
                            border.width: 1; border.color: App.Theme.hairline
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.n
                                font.family: App.Theme.font
                                font.pixelSize: App.Theme.fontSize - 1
                                color: App.ThemeState.dark === parent.modelData.d ? App.Theme.bg : App.Theme.fg
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: App.ThemeState.setKey("dark", parent.modelData.d)
                            }
                        }
                    }
                }

                // ── presets ──
                Text {
                    text: "presets" + (App.ThemeState.presets.length ? "" : " — none saved yet")
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1
                    color: App.Theme.muted
                }
                Flow {
                    width: parent.width; spacing: 7
                    Repeater {
                        model: App.ThemeState.presets
                        Rectangle {
                            required property var modelData
                            width: 30; height: 30; radius: 15
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: modelData.a }
                                GradientStop { position: 1.0; color: modelData.b }
                            }
                            border.width: 2
                            border.color: App.ThemeState.themeName === modelData.name
                                          ? App.PowerProfile.accentBri : Qt.rgba(1, 1, 1, 0.12)
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton)
                                        App.ThemeState.deletePreset(parent.modelData.slug)
                                    else
                                        App.ThemeState.loadPreset(parent.modelData.slug)
                                }
                            }
                        }
                    }
                }

                // ── live preview ──
                Text {
                    text: "preview"
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1
                    color: App.Theme.muted
                }
                Rectangle {
                    width: parent.width; height: 46
                    radius: App.Theme.islandRadius
                    color: App.Theme.panel
                    border.width: 1; border.color: App.PowerProfile.accent
                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Text {
                            text: "◕▿◕"; font.family: App.Theme.font
                            font.pixelSize: App.Theme.fontSize + 2
                            color: App.PowerProfile.accentBri
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Row {
                            spacing: 5
                            anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                model: 4
                                Rectangle {
                                    required property int index
                                    width: index === 1 ? 13 : 9
                                    height: width; radius: width / 2
                                    color: index === 1 ? App.PowerProfile.accent
                                         : index === 0 ? App.Theme.dim : App.Theme.surface2
                                }
                            }
                        }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        text: "12:34"
                        font.family: App.Theme.font
                        font.pixelSize: App.Theme.fontSize
                        color: App.Theme.fg
                    }
                }

                // name + save
                Row {
                    width: parent.width; spacing: 8
                    Rectangle {
                        width: parent.width - 78 - 8; height: 30
                        radius: App.Theme.pillRadius
                        color: App.Theme.surface2
                        border.width: 1
                        border.color: nameField.activeFocus ? App.PowerProfile.accent : App.Theme.hairline
                        TextInput {
                            id: nameField
                            anchors { fill: parent; margins: 8 }
                            verticalAlignment: TextInput.AlignVCenter
                            text: App.ThemeState.themeName
                            font.family: App.Theme.font
                            font.pixelSize: App.Theme.fontSize - 1
                            color: App.Theme.fg
                            selectByMouse: true
                            clip: true
                            onAccepted: App.ThemeState.savePreset(text)
                        }
                    }
                    Rectangle {
                        width: 78; height: 30; radius: App.Theme.pillRadius
                        color: App.Theme.surface2
                        border.width: 1; border.color: App.PowerProfile.accent
                        Text {
                            anchors.centerIn: parent; text: "save"
                            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1
                            color: App.PowerProfile.accentBri
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: App.ThemeState.savePreset(nameField.text)
                        }
                    }
                }

                // ── keyboard backlight ──
                // The FX506HF backlight is SINGLE ZONE — one colour for the whole
                // keyboard. Per-key is not possible on this hardware.
                Item {
                    width: parent.width; height: 26
                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Text {
                            text: "󰌌"
                            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 3
                            color: App.PowerProfile.accentBri
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "keyboard"
                            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                            color: App.Theme.muted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 30; height: 18; radius: 5
                        visible: App.ThemeState.kbdMode !== "off"
                        color: App.ThemeState.kbdEffective
                        border.width: 1; border.color: App.Theme.hairline
                    }
                }
                Row {
                    width: parent.width; spacing: 6
                    Repeater {
                        model: [{ m: "a", n: "match A" }, { m: "b", n: "match B" },
                                { m: "custom", n: "custom" }, { m: "off", n: "off" }]
                        Rectangle {
                            required property var modelData
                            width: (col.width - 18) / 4; height: 28
                            radius: App.Theme.pillRadius
                            color: App.ThemeState.kbdMode === modelData.m
                                   ? App.PowerProfile.accent : App.Theme.surface2
                            border.width: 1
                            border.color: App.ThemeState.kbdMode === modelData.m
                                          ? App.PowerProfile.accentBri : App.Theme.hairline
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.n
                                font.family: App.Theme.font
                                font.pixelSize: App.Theme.fontSize - 3
                                color: App.ThemeState.kbdMode === parent.modelData.m
                                       ? App.Theme.bg : App.Theme.fg
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: App.ThemeState.setKbd("mode", parent.modelData.m)
                            }
                        }
                    }
                }
                // its own wheel, only when you're not matching a gradient stop
                Row {
                    width: parent.width
                    spacing: 12
                    visible: App.ThemeState.kbdMode === "custom"
                    C.ColorWheel {
                        id: kbdWheel
                        width: 120; height: 120
                        lightness: 0.55
                        value: App.ThemeState.kbdColour
                        onPicked: c => App.ThemeState.setKbd("colour", c.toString().substring(0, 7))
                    }
                    Column {
                        width: parent.width - 120 - 12
                        spacing: 8
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: parent.width; height: 34; radius: App.Theme.pillRadius
                            color: App.ThemeState.kbdColour
                            border.width: 1; border.color: App.Theme.hairline
                        }
                        Text {
                            text: App.ThemeState.kbdColour
                            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                            color: App.Theme.fg
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "single-zone hardware — the whole keyboard is one colour"
                            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 3
                            color: App.Theme.muted
                        }
                    }
                }

                // ── customize ──
                Rectangle { width: parent.width; height: 1; color: App.Theme.hairline }
                Text {
                    text: "customize"
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1
                    color: App.Theme.muted
                }

                // font — opens its own view (817 raw family names is not a dropdown)
                Rectangle {
                    width: parent.width; height: 40
                    radius: App.Theme.pillRadius
                    color: App.Theme.surface2
                    border.width: 1; border.color: App.Theme.hairline
                    Text {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "font"
                        font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                        color: App.Theme.muted
                    }
                    Text {
                        anchors { right: arrow.left; rightMargin: 8; verticalCenter: parent.verticalCenter
                                  left: parent.left; leftMargin: 56 }
                        horizontalAlignment: Text.AlignRight
                        text: App.ThemeState.fontFamily
                        elide: Text.ElideLeft
                        font.family: App.ThemeState.fontFamily
                        font.pixelSize: App.Theme.fontSize + 1
                        color: App.Theme.fg
                    }
                    Text {
                        id: arrow
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "›"
                        font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 2
                        color: App.PowerProfile.accentBri
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: panel.fontView = true
                    }
                }

                C.LabeledSlider {
                    width: parent.width; label: "font size"; from: 8; to: 20
                    value: App.ThemeState.fontSize
                    onMoved: v => App.ThemeState.setKey("fontSize", Math.round(v))
                }
                C.LabeledSlider {
                    width: parent.width; label: "app font ±"; from: -4; to: 8
                    value: App.ThemeState.fontDelta
                    onMoved: v => App.ThemeState.setKey("fontDelta", Math.round(v))
                }
                C.LabeledSlider {
                    width: parent.width; label: "rounding"; from: 0; to: 30
                    value: App.ThemeState.rounding
                    onMoved: v => App.ThemeState.setKey("rounding", Math.round(v))
                }
                C.LabeledSlider {
                    width: parent.width; label: "gaps in"; from: 0; to: 30
                    value: App.ThemeState.gapsIn
                    onMoved: v => App.ThemeState.setKey("gapsIn", Math.round(v))
                }
                C.LabeledSlider {
                    width: parent.width; label: "gaps out"; from: 0; to: 60
                    value: App.ThemeState.gapsOut
                    onMoved: v => App.ThemeState.setKey("gapsOut", Math.round(v))
                }
                C.LabeledSlider {
                    width: parent.width; label: "blur"; from: 0; to: 8
                    value: App.ThemeState.blur
                    onMoved: v => App.ThemeState.setKey("blur", Math.round(v))
                }
                C.LabeledSlider {
                    width: parent.width; label: "anim"; from: 0; to: 600; suffix: "ms"
                    value: App.ThemeState.anim
                    onMoved: v => App.ThemeState.setKey("anim", Math.round(v))
                }
                C.LabeledSlider {
                    width: parent.width; label: "bar height"; from: 24; to: 52
                    value: App.ThemeState.barHeight
                    onMoved: v => App.ThemeState.setKey("barHeight", Math.round(v))
                }
                C.LabeledSlider {
                    width: parent.width; label: "inactive op"; from: 0.4; to: 1.0; decimals: 2
                    value: App.ThemeState.opacity_
                    onMoved: v => App.ThemeState.setKey("opacity", v)
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "blur > 0 re-renders over the animated wallpaper every frame on the Intel iGPU — that is the known choppiness trade-off."
                    font.family: App.Theme.font
                    font.pixelSize: App.Theme.fontSize - 3
                    color: App.Theme.muted
                    visible: App.ThemeState.blur > 0
                }

                // ── wallpaper ──
                Rectangle { width: parent.width; height: 1; color: App.Theme.hairline }
                Text {
                    text: "wallpaper · click = set · ⟳ = re-record · right-click = chat"
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1
                    color: App.Theme.muted
                }
                // Same deal as the sub-views above: the grid rescans the library on
                // creation, so it only exists while the panel is actually open.
                Loader {
                    width: parent.width
                    height: 260
                    active: panel.open
                    sourceComponent: C.WallGrid {
                        onEditLoop: w => { panel.loopWp = w; panel.loopView = true }
                    }
                }

                // ── wallpaper sound ──
                Rectangle {
                    width: parent.width; height: 40
                    radius: App.Theme.pillRadius
                    color: App.ThemeState.wpAudio
                           ? Qt.rgba(App.PowerProfile.accent.r, App.PowerProfile.accent.g,
                                     App.PowerProfile.accent.b, 0.20) : App.Theme.surface2
                    border.width: 1
                    border.color: App.ThemeState.wpAudio ? App.PowerProfile.accent : App.Theme.hairline
                    Behavior on color { ColorAnimation { duration: App.Theme.animF } }
                    Row {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 9
                        Text {
                            text: App.ThemeState.wpAudio ? "󰕾" : "󰖁"
                            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize + 4
                            color: App.ThemeState.wpAudio ? App.PowerProfile.accentBri : App.Theme.muted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "wallpaper sound"
                            font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize
                            color: App.Theme.fg
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: App.ThemeState.setWp("audio", !App.ThemeState.wpAudio)
                    }
                }
                C.LabeledSlider {
                    width: parent.width; label: "volume"; from: 0; to: 100
                    value: App.ThemeState.wpVolume
                    enabled: App.ThemeState.wpAudio
                    opacity: App.ThemeState.wpAudio ? 1.0 : 0.45
                    onMoved: v => App.ThemeState.setWp("volume", Math.round(v))
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "mutes itself while anything else plays audio, or while a window is fullscreen. Sound + volume apply live — no re-convert needed."
                    font.family: App.Theme.font
                    font.pixelSize: App.Theme.fontSize - 3
                    color: App.Theme.muted
                }

                // ── lockscreen wallpaper ──
                Rectangle { width: parent.width; height: 1; color: App.Theme.hairline }
                Text {
                    text: "lockscreen background"
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1
                    color: App.Theme.muted
                }
                Row {
                    width: parent.width; spacing: 6
                    Repeater {
                        model: [{ m: "wallpaper", n: "wallpaper" }, { m: "static", n: "art" },
                                { m: "off", n: "leave" }]
                        Rectangle {
                            required property var modelData
                            width: (col.width - 12) / 3; height: 28
                            radius: App.Theme.pillRadius
                            color: App.ThemeState.lockMode === modelData.m
                                   ? App.PowerProfile.accent : App.Theme.surface2
                            border.width: 1
                            border.color: App.ThemeState.lockMode === modelData.m
                                          ? App.PowerProfile.accentBri : App.Theme.hairline
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.n
                                font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 3
                                color: App.ThemeState.lockMode === parent.modelData.m
                                       ? App.Theme.bg : App.Theme.fg
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: App.ThemeState.setLock("mode", parent.modelData.m)
                            }
                        }
                    }
                }
                C.LabeledSlider {
                    width: parent.width
                    label: "frame at"; from: 0; to: 30; suffix: "s"
                    visible: App.ThemeState.lockMode === "wallpaper"
                    value: App.ThemeState.lock.frame !== undefined ? App.ThemeState.lock.frame : 3
                    onMoved: v => App.ThemeState.setLock("frame", Math.round(v))
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: App.ThemeState.lockMode === "wallpaper"
                    text: "hyprlock takes a still image, so this grabs a frame from your wallpaper video at that timestamp. Applied on the next theme apply."
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 3
                    color: App.Theme.muted
                }

                Text {
                    text: "conversion quality (scene → mp4)"
                    font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1
                    color: App.Theme.muted
                }
                C.LabeledSlider {
                    width: parent.width; label: "fps"; from: 24; to: 60
                    value: App.ThemeState.wp.fps
                    onMoved: v => App.ThemeState.setWp("fps", Math.round(v))
                }
                C.LabeledSlider {
                    width: parent.width; label: "length"; from: 10; to: 60; suffix: "s"
                    value: App.ThemeState.wp.seconds
                    onMoved: v => App.ThemeState.setWp("seconds", Math.round(v))
                }
                C.LabeledSlider {
                    width: parent.width; label: "quality"; from: 0; to: 34
                    value: 34 - App.ThemeState.wp.crf
                    onMoved: v => App.ThemeState.setWp("crf", Math.round(34 - v))
                }

                Item { width: 1; height: 6 }
            }
        }

        // ── apply / revert, pinned to the bottom ──
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
            height: 38
            radius: App.Theme.pillRadius
            color: "transparent"

            Row {
                anchors.fill: parent
                spacing: 8

                Rectangle {
                    width: (parent.width - 8) * 0.62; height: parent.height
                    radius: App.Theme.pillRadius
                    color: App.ThemeState.dirty ? App.PowerProfile.accent : App.Theme.surface2
                    opacity: App.ThemeState.busy ? 0.6 : 1.0
                    Behavior on color { ColorAnimation { duration: App.Theme.animF } }
                    Text {
                        anchors.centerIn: parent
                        text: App.ThemeState.busy ? "applying…" : "apply to everything"
                        font.family: App.Theme.font
                        font.pixelSize: App.Theme.fontSize - 1
                        font.bold: true
                        color: App.ThemeState.dirty ? App.Theme.bg : App.Theme.muted
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: App.ThemeState.apply()
                    }
                }
                Rectangle {
                    width: (parent.width - 8) * 0.38; height: parent.height
                    radius: App.Theme.pillRadius
                    color: App.Theme.surface2
                    border.width: 1; border.color: App.Theme.hairline
                    Text {
                        anchors.centerIn: parent; text: "revert"
                        font.family: App.Theme.font; font.pixelSize: App.Theme.fontSize - 1
                        color: App.Theme.fg
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: App.ThemeState.revert()
                    }
                }
            }
        }

    }

    // Click-away to close, behind the sheet.
    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: panel.open
        onClicked: App.Bus.theme = false
    }
}
