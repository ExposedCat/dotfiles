import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property var shell
    property var sample: ({})
    property var history: []
    readonly property real sampleTime: history.length ? history[history.length - 1].time : 0
    readonly property var vram: vramPercent(sample)
    property string error: ""
    readonly property bool active: shell.panel === "system" && !shell.pillHidden
    function update(data, sampledAt) {
        if (data.error) { error = "System statistics are unavailable."; return; }
        sample = data; error = "";
        const time = sampledAt === undefined ? Date.now() : sampledAt;
        history = history.filter(point => point.time >= time - 60000 && point.time < time)
            .concat([{time: time, cpu: data.cpu, memory: data.memory, gpu: data.gpu, vram: vramPercent(data)}]).slice(-61);
    }
    function vramPercent(data) {
        const used = data.vramUsed, total = data.vramTotal;
        return typeof used === "number" && Number.isFinite(used) && used >= 0
            && typeof total === "number" && Number.isFinite(total) && total > 0 ? used * 100 / total : null;
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
        command: [root.shell.backend, "shell", "stats-watch"]
        running: root.active && !root.shell.fixture
        stdout: SplitParser { onRead: line => { try { root.update(JSON.parse(line)); } catch(e) { root.error = "Could not read system statistics."; } } }
        onExited: (code, status) => { if (code !== 0 && root.active) root.error = "System statistics are unavailable."; }
    }
    Timer { interval: 1000; repeat: true; running: root.active && root.shell.fixture; onTriggered: root.fixtureUpdate() }
}
