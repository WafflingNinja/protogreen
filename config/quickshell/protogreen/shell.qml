//  ╔═══════════════════════════════════════════════╗
//  ║  PROTO//GREEN — quickshell visor bar + HUD      ║
//  ║  toggle to waybar: SUPER+SHIFT+B                ║
//  ╚═══════════════════════════════════════════════╝
import Quickshell
import Quickshell.Io

ShellRoot {
    // visor bar, one per monitor
    Variants {
        model: Quickshell.screens
        Bar {}
    }
    // slide-out HUD, one per monitor
    Variants {
        model: Quickshell.screens
        Hud {}
    }
    // volume/brightness OSD, one per monitor
    Variants {
        model: Quickshell.screens
        Osd {}
    }

    // NULL assistant popup, one per monitor
    Variants {
        model: Quickshell.screens
        AssistantPopup {}
    }

    // Pip's login greeting, one per monitor
    Variants {
        model: Quickshell.screens
        GreetToast {}
    }

    // theme panel, one per monitor
    Variants {
        model: Quickshell.screens
        ThemePanel {}
    }

    // crosshair overlay, one per monitor
    Variants {
        model: Quickshell.screens
        Crosshair {}
    }

    // keyboard control:  qs -c protogreen ipc call hud toggle
    IpcHandler {
        target: "hud"
        function toggle(): void { Bus.hud = !Bus.hud }
        function show(): void { Bus.hud = true }
        function hide(): void { Bus.hud = false }
    }

    // qs -c protogreen ipc call ai toggle
    IpcHandler {
        target: "ai"
        function toggle(): void { Bus.assistant = !Bus.assistant }
        function show(): void { Bus.assistant = true }
        function hide(): void { Bus.assistant = false }
    }

    // qs -c protogreen ipc call theme toggle
    IpcHandler {
        target: "theme"
        function toggle(): void { Bus.toggleTheme() }
        function show(): void { Bus.theme = true }
        function hide(): void { Bus.theme = false }
    }

    // qs -c protogreen ipc call capture on|off  (used by wpconvert.sh)
    IpcHandler {
        target: "capture"
        function on(): void { Bus.capture = true; Bus.hud = false; Bus.theme = false; Bus.assistant = false }
        function off(): void { Bus.capture = false }
    }

    // qs -c protogreen ipc call crosshair toggle  (F4 bind)
    IpcHandler {
        target: "crosshair"
        function toggle(): void { Bus.toggleCrosshair() }
        function show(): void { Bus.crosshair = true }
        function hide(): void { Bus.crosshair = false }
    }

    // qs -c protogreen ipc call visor sleep|wake  (driven by hypridle)
    IpcHandler {
        target: "visor"
        function sleep(): void { Bus.asleep = true }
        function wake(): void { Bus.asleep = false }
    }
}
