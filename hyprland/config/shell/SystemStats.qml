import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property var shell
    property var sample: ({})
    property var history: []
    property string error: ""
    readonly property bool active: shell.panel === "system" && !shell.pillHidden
    function update(data) {
        if (data.error) { error = "System statistics are unavailable."; return; }
        sample = data; error = "";
        history = history.concat([{cpu: data.cpu, memory: data.memory, gpu: data.gpu}]).slice(-60);
    }
    function bytes(value) {
        if (value === null || value === undefined) return "—";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
        return value.toFixed(unit > 1 ? 1 : 0) + " " + units[unit];
    }
    function fixtureUpdate() {
        update(shell.fixtureData.stats || {cpu: 23, memory: 48, memoryUsed: 16e9, memoryTotal: 32e9, gpu: 15, gpuTemperature: 49, cpuTemperature: 51, vramUsed: 3e9, vramTotal: 8e9, down: 1500000, up: 230000, disk: 37, diskUsed: 370e9, diskTotal: 1e12, swapUsed: 0, uptime: 14400});
    }
    onActiveChanged: { if (active && shell.fixture) fixtureUpdate(); }
    Process {
        id: reader
        command: ["/usr/bin/python3", root.shell.backend, "stats-watch"]
        running: root.active && !root.shell.fixture
        stdout: SplitParser { onRead: line => { try { root.update(JSON.parse(line)); } catch(e) { root.error = "Could not read system statistics."; } } }
        onExited: (code, status) => { if (code !== 0 && root.active) root.error = "System statistics are unavailable."; }
    }
    Timer { interval: 1000; repeat: true; running: root.active && root.shell.fixture; onTriggered: root.fixtureUpdate() }
}
