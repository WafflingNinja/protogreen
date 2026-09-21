pragma Singleton
import Quickshell

// Tiny shared state bus (bar <-> HUD panel <-> assistant popup).
Singleton {
    property bool hud: false
    function toggleHud() { hud = !hud }

    // NULL — the live assistant popup
    property bool assistant: false
    function toggleAssistant() { assistant = !assistant }

    // theme panel (colour wheel + customize + wallpaper grid)
    property bool theme: false
    function toggleTheme() { theme = !theme; if (theme) hud = false }

    // visor sleep state (driven by hypridle, ~30s before lock)
    property bool asleep: false

    // crosshair overlay (F4 / HUD toggle)
    property bool crosshair: false
    function toggleCrosshair() { crosshair = !crosshair }

    // Capture mode: hide EVERY protogreen surface so wpconvert.sh can record the
    // wallpaper layer clean. These are layer surfaces sitting above the wallpaper,
    // so anything still mapped gets baked into the video.
    //
    // This exists because the old approach — `pkill -x qs` from inside the script —
    // was suicide: the panel launches wpconvert.sh as a CHILD of qs, so killing qs
    // killed the conversion with it and no scene ever finished recording.
    property bool capture: false
}
