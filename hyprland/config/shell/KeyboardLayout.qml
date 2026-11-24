import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root
    required property var shell
    property string layout: "English (US)"
    property string keyboard: ""
    property int revision: 0
    property int queryRevision: 0
    property bool refreshPending: false
    function applySnapshot(data, sinceRevision) {
        // A reply started before a newer layout event must not undo that event.
        if (sinceRevision !== undefined && sinceRevision !== revision) return false;
        // session-info uses an empty keyboard on unavailable/transient IPC data.
        // Keep the last known layout until there is a real primary keyboard.
        if (typeof data.keyboard !== "string" || !data.keyboard.length || typeof data.layout !== "string" || !data.layout.length) return false;
        keyboard = data.keyboard;
        layout = data.layout;
        return true;
    }
    function refresh() {
        if (shell.fixture) return;
        if (reader.running) { refreshPending = true; return; }
        refreshPending = false;
        queryRevision = revision;
        reader.running = true;
    }
    function handleEvent(name, data) {
        if (name === "activelayout") {
            const comma = data.indexOf(",");
            if (comma < 1 || comma === data.length - 1) return;
            const device = data.slice(0, comma), nextLayout = data.slice(comma + 1);
            revision++;
            if (!keyboard || device === keyboard) {
                keyboard = device;
                layout = nextLayout;
            }
            // Another keyboard may have become primary since the last query.
            refreshDelay.restart();
        } else if (["configreloaded", "deviceadded", "deviceremoved"].includes(name)) refreshDelay.restart();
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { root.handleEvent(event.name, event.data); }
    }
    Process {
        id: reader
        command: [root.shell.backend, "shell", "session-info"]
        stdout: SplitParser {
            onRead: line => {
                try { root.applySnapshot(JSON.parse(line), root.queryRevision); }
                catch (e) { console.warn("Invalid keyboard layout status:", e); }
            }
        }
        onExited: { if (root.refreshPending || root.queryRevision !== root.revision) refreshDelay.restart(); }
    }
    Timer { id: refreshDelay; interval: 80; onTriggered: root.refresh() }
    // Layout events drive updates; this only reconciles an event missed while IPC reconnects.
    Timer { interval: 60000; running: !root.shell.fixture; repeat: true; onTriggered: root.refresh() }
    Component.onCompleted: refresh()
}
