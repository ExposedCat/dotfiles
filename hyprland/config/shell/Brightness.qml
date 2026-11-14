import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property var shell
    property var devices: []
    property string error: ""
    property var queued: null
    property var applying: null
    property real updatedAt: 0
    readonly property bool loading: reader.running
    readonly property bool busy: writer.running
    function refresh() {
        if (shell.fixture) { devices = shell.fixtureData.brightnessDevices || [{name: "DP-3", description: "Main monitor", level: 0.65, supported: true}]; return; }
        if (!reader.running && !writer.running && Date.now() - updatedAt > 15000) reader.running = true;
    }
    function updateLevel(output, value) { devices = devices.map(d => d.name === output ? Object.assign({}, d, {level: value}) : d); }
    function setLevel(output, value) {
        value = Math.max(0, Math.min(1, value));
        updateLevel(output, value);
        if (shell.fixture) {
            shell.fixtureEvent("brightness", {output: output, level: value});
            shell.osd.showBrightness(output, Math.round(value * 100), 100);
            return;
        }
        queued = {name: output, level: value};
        applyNext();
    }
    function applyNext() {
        if (writer.running || !queued) return;
        applying = queued; queued = null; error = "";
        writer.command = ["/usr/bin/python3", shell.backend, "brightness-set", applying.name, String(applying.level)];
        writer.running = true;
    }
    Process {
        id: reader
        command: ["/usr/bin/python3", root.shell.backend, "brightness-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.devices = JSON.parse(text).devices; root.updatedAt = Date.now(); root.error = ""; }
                catch(e) { root.error = "Could not read monitor brightness."; }
            }
        }
        onExited: (code, status) => { if (code !== 0) root.error = "Could not read monitor brightness."; }
    }
    Process {
        id: writer
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (!root.queued || root.queued.name !== result.name) root.updateLevel(result.name, result.level);
                    root.shell.osd.showBrightness(result.name, result.current, result.maximum);
                } catch(e) { root.error = "Could not set monitor brightness."; }
            }
        }
        onExited: (code, status) => { if (code !== 0) root.error = "Could not set monitor brightness."; Qt.callLater(root.applyNext); }
    }
    Connections { target: root.shell; function onPanelChanged() { if (root.shell.panel === "mixer") root.refresh(); } }
}
