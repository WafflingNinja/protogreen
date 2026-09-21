pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Pip — live local assistant (llama3.2:3b via ollama, on the RTX 2050).
// A deterministic router handles ALL routing (desktop commands + explicit web
// search); the model is used purely for warm conversational prose, which small
// models are good at — never for classification, which they are not.
// Model unloads the moment the popup closes (frees the dGPU).
Singleton {
    id: root

    readonly property string model: "llama3.2:3b"
    property string system: ""
    property var history: []
    readonly property int maxTurns: 8

    property bool busy: false
    property string reply: ""
    property string lastAction: ""

    signal replied()

    property string pendingQuery: ""
    property string lastUserMsg: ""
    property bool   autoSearched: false      // guards against re-searching the same turn
    readonly property string searchScript: Qt.resolvedUrl("assistant/websearch.py").toString().replace("file://", "")

    // ── load persona ──
    readonly property string personaPath: Qt.resolvedUrl("assistant/persona.txt").toString().replace("file://", "")
    Process {
        running: true
        command: ["cat", root.personaPath]
        stdout: StdioCollector { onStreamFinished: root.system = this.text }
    }

    // ── entry point ──
    function send(text) {
        if (busy || !text || !text.trim()) return
        var msg = text.trim()
        var r = _route(msg)

        if (r && r.verb === "search") {            // explicit web search
            history.push({ role: "user", content: msg })
            reply = r.reply
            busy = true
            autoSearched = true                    // summary reply must not re-escalate
            pendingQuery = r.arg
            search.command = ["python3", root.searchScript, r.arg]
            search.running = true
            return
        }
        if (r) {                                   // instant desktop command, no LLM
            history.push({ role: "user", content: msg })
            reply = r.reply
            history.push({ role: "assistant", content: reply })
            _runAction(r.verb, r.arg)
            replied()
            return
        }

        // plain conversation → the model just talks (and may auto-search if unsure)
        history.push({ role: "user", content: msg })
        if (history.length > maxTurns * 2)
            history = history.slice(history.length - maxTurns * 2)
        lastUserMsg = msg
        autoSearched = false
        reply = ""
        busy = true
        _ask(history)
    }

    function clear() { history = []; reply = ""; lastAction = ""; pendingQuery = "" }

    // ── deterministic router: {verb,arg,reply} or null ──
    function _route(text) {
        var s = " " + text.toLowerCase().trim() + " "
        var m

        // explicit web search
        m = text.match(/\b(?:search(?:\s+the\s+web)?(?:\s+for)?|look\s*up|google|find\s+(?:online|on\s+the\s+web)|web\s*search(?:\s+for)?)\b[:\s]+(.+)/i)
        if (m && m[1].trim()) return { verb: "search", arg: m[1].trim(), reply: "Let me look that up for you ^^" }

        // open / launch an app
        m = s.match(/\b(?:open|launch|start|run|fire up|pop open)\s+(?:up\s+|my\s+|the\s+)?([a-z]+)/)
        if (m && apps[m[1]]) return { verb: "app", arg: m[1], reply: "Opening " + m[1] + " for you ^^" }

        // workspace
        m = s.match(/\b(?:workspace|desktop|ws)\s*#?\s*([1-9]|10)\b/) || s.match(/\bgo to (?:workspace |desktop )?([1-9]|10)\b/)
        if (m) return { verb: "workspace", arg: m[1], reply: "Workspace " + m[1] + ", coming up~" }

        // night mode
        if (/\b(?:night ?mode|night ?light|blue ?light)\b/.test(s)) {
            var off = /\b(?:off|disable|stop)\b/.test(s)
            return { verb: "night", arg: off ? "off" : "on", reply: off ? "Night mode off ^^" : "Night mode on — easy on those eyes." }
        }

        // mute / volume
        if (/\bmute\b/.test(s)) return { verb: "volume", arg: "mute", reply: "Muted~ 🤫" }
        m = s.match(/\b(?:volume|sound|audio)\b[^0-9]*(\d{1,3})\b/) || s.match(/\b(\d{1,3})%?\s*(?:volume|sound)\b/)
        if (m) return { verb: "volume", arg: m[1], reply: "Volume to " + m[1] + " ^^" }

        // brightness
        m = s.match(/\bbright(?:ness)?\b[^0-9]*(\d{1,3})\b/)
        if (m) return { verb: "brightness", arg: m[1], reply: "Brightness at " + m[1] + " ^^" }

        // screenshot
        if (/\b(?:screenshot|screen ?shot|screencap|screen ?grab)\b/.test(s)) {
            var mode = /\bwindow\b/.test(s) ? "window" : (/\b(?:full|whole|entire|everything|all)\b/.test(s) ? "full" : "region")
            return { verb: "screenshot", arg: mode, reply: "Say cheese ^^" }
        }

        // lock
        if (/\block\b/.test(s) && !/\bunlock\b/.test(s)) return { verb: "lock", arg: "", reply: "Locking up~ stay safe, operator" }

        // showcase
        if (/\bshowcase\b/.test(s)) return { verb: "showcase", arg: "", reply: "Showtime~ ◕▿◕" }

        return null
    }

    // ── model call (plain prose, no structured format) ──
    function _ask(msgs) {
        var body = JSON.stringify({
            model: model,
            messages: [{ role: "system", content: system }].concat(msgs),
            stream: false,
            keep_alive: "45s",
            options: { temperature: 0.6, num_predict: 320 }
        })
        chat.environment = { "BODY": body }
        chat.running = true
    }

    Process {
        id: chat
        command: ["bash", "-c", "printf '%s' \"$BODY\" | curl -s --max-time 120 http://localhost:11434/api/chat -d @-"]
        stdout: StdioCollector { onStreamFinished: root._handle(this.text) }
        onExited: (code, status) => {
            if (root.busy && root.pendingQuery === "") {
                root.reply = "no model here — chat needs ollama running (see README). desktop commands still work ^^"
                root.busy = false
                root.replied()
            }
        }
    }

    function _handle(raw) {
        if (!busy) return
        // Nothing came back at all → no ollama listening. Optional dependency, so say
        // so plainly instead of pretending the model got confused.
        if (!raw || raw.trim() === "") {
            reply = "no model here — chat needs ollama running (see README). desktop commands still work ^^"
            busy = false
            replied()
            return
        }
        var out = ""
        try { out = (JSON.parse(raw).message.content || "").trim() }
        catch (e) { out = "…my thoughts got tangled, say that again? ◔_◔" }

        // auto-escalate to web search if Pip sounds unsure (once per turn)
        if (!autoSearched && lastUserMsg && _soundsUnsure(out)) {
            autoSearched = true
            reply = "hmm, let me double-check that online ^^"
            pendingQuery = lastUserMsg
            search.command = ["python3", root.searchScript, lastUserMsg]
            search.running = true
            return                                  // stays busy → _afterSearch re-answers
        }

        reply = out || "mm-hm ^^"
        history.push({ role: "assistant", content: reply })
        busy = false
        replied()
    }

    // does the model's own reply admit it isn't sure / may be stale?
    function _soundsUnsure(t) {
        var s = t.toLowerCase()
        return /(i'?m not (sure|certain)|i (don'?t|do not) (know|have)|not entirely sure|i'?m unsure|out of date|as of my (last|knowledge|training)|i (don'?t|do not) have (access|real[- ]?time|current|up[- ]?to[- ]?date|the latest)|my (knowledge|training) (cut-?off|data)|might be (outdated|out of date)|may have changed|can'?t be sure|no information)/.test(s)
    }

    // ── web search (run by router), then summarise with the model ──
    Process {
        id: search
        stdout: StdioCollector { onStreamFinished: root._afterSearch(this.text) }
        onExited: (code, status) => { if (root.busy && root.pendingQuery !== "") root._afterSearch("") }
    }

    function _afterSearch(results) {
        if (!busy) return
        var r = (results || "").trim()
        var note
        if (!r || r === "NO_RESULTS" || r === "NO_QUERY")
            note = "(web search for \"" + pendingQuery + "\" found nothing). Tell the operator you couldn't reach the web, and answer briefly from what you know if you can."
        else
            note = "Here are fresh web results for \"" + pendingQuery + "\":\n" + r + "\n\nAnswer the operator concisely (1-3 sentences) using these, stating the key fact."
        pendingQuery = ""
        _ask(history.concat([{ role: "user", content: note }]))
    }

    // ── unload the model when the popup closes (instant dGPU free) ──
    Connections {
        target: Bus
        function onAssistantChanged() {
            if (!Bus.assistant && !root.busy) unload.running = true
        }
    }
    Process { id: unload; command: ["ollama", "stop", root.model] }

    // ── desktop control: fixed whitelist, no arbitrary shell ──
    readonly property var apps: ({
        kitty: "kitty", terminal: "kitty", thunar: "thunar", files: "thunar",
        firefox: "firefox", browser: "firefox", code: "code", vscode: "code",
        discord: "vesktop", spotify: "spotify", rofi: "rofi -show drun"
    })
    function _runAction(verb, arg) {
        var cmd = ""
        var a = (arg || "").toLowerCase()
        if (verb === "app") {
            cmd = "exec " + (apps[a] || "rofi -show drun")
        } else if (verb === "workspace") {
            var n = parseInt(arg)
            if (n >= 1 && n <= 10) cmd = (Compositor.sway ? "workspace number " : "workspace ") + n
        } else if (verb === "night") {
            cmd = "exec " + (a === "off" ? Compositor.nightOffCmd : Compositor.nightOnCmd)
        } else if (verb === "lock") {
            cmd = "exec " + Compositor.lockCmd
        } else if (verb === "volume") {
            if (a === "mute") cmd = "exec pamixer -t"
            else { var v = parseInt(arg); if (v >= 0 && v <= 100) cmd = "exec pamixer --set-volume " + v }
        } else if (verb === "brightness") {
            var b = parseInt(arg); if (b >= 0 && b <= 100) cmd = "exec brightnessctl set " + b + "%"
        } else if (verb === "screenshot") {
            var mode = (a === "window" || a === "full") ? a : "region"
            cmd = "exec __HOME__/.config/hypr/scripts/screenshot.sh " + mode
        } else if (verb === "showcase") {
            cmd = "exec kitty -e __HOME__/.config/hypr/scripts/showcase.sh"
        }
        if (cmd) { Compositor.dispatch(cmd); lastAction = verb + (arg && verb !== "lock" && verb !== "showcase" ? " " + arg : "") }
    }
}
