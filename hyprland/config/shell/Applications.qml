import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property var shell
    property var installed: []
    readonly property var apps: shell.fixture ? (shell.fixtureData.apps || []) : installed
    property var usage: ({})
    property string error: ""
    property real updatedAt: 0
    property bool ready: false
    readonly property bool loading: reader.running
    function refresh() {
        if (!shell.fixture && !reader.running && (!updatedAt || Date.now() - updatedAt > 60000)) reader.running = true;
    }
    function record(id) {
        const next = Object.assign({}, usage);
        next[id] = Math.min(1000000, (Number(next[id]) || 0) + 1);
        usage = next;
        if (!shell.fixture) save.restart();
    }
    Component.onCompleted: {
        try { const data = JSON.parse(history.text()); if (data.version === 1 && data.usage) usage = data.usage; } catch(e) {}
        ready = true;
    }
    FileView {
        id: history
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dotfiles/hyprland/launcher-usage.json"
        blockLoading: true; printErrors: false; atomicWrites: true
    }
    Timer { id: save; interval: 200; onTriggered: history.setText(JSON.stringify({version: 1, usage: root.usage})) }
    Process {
        id: reader
        command: ["/usr/bin/python3", root.shell.helper, "apps-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (!Array.isArray(data)) throw Error("Invalid application index");
                    root.installed = data; root.updatedAt = Date.now(); root.error = "";
                } catch(e) { root.error = "Could not load applications."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) console.warn("Application index:", text.trim()); } }
        onExited: (code, status) => { if (code !== 0) root.error = "Could not load applications."; }
    }
}
