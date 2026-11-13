import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    property var devices: []
    property bool unavailable: false
    property var result: null
    property string phase: ""
    property string testError: ""
    readonly property bool testing: testProcess.running || fixtureTest.running
    readonly property string resultPath: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/dotfiles/hyprland/internet-speed.json"
    function speed(value) {
        if (value === undefined || value === null) return "—";
        return value >= 1000 ? (value / 1000).toFixed(2) + " Gb/s" : value.toFixed(1) + " Mb/s";
    }
    function update(data) {
        const status = data.devices.map(d => ({name: d.name, state: d.state, speed: d.speed, connected: d.connected}));
        // Quiet status polling must not rebuild controls or animate refresh.
        if (JSON.stringify(status) !== JSON.stringify(devices)) devices = status;
        unavailable = !!data.unavailable;
    }
    function refreshStatus() {
        if (shell.fixture) { update({devices: shell.fixtureData.ethernetDevices || [{name: "enp5s0", state: "Connected", speed: 1000, connected: true}]}); return }
        if (!reader.running) reader.running = true;
    }
    function testSpeed() {
        if (testing) return;
        testError = ""; phase = "download";
        if (shell.fixture) fixtureTest.start();
        else testProcess.running = true;
    }
    function loadResult() {
        if (shell.fixture) { result = shell.fixtureData.internetSpeed || null; return }
        try {
            const data = JSON.parse(saved.text());
            const value = data.result;
            if (data.version === 1 && value && Number.isFinite(value.download) && Number.isFinite(value.upload) && value.measuredAt > 0) result = value;
        } catch (e) { /* No previous measurement yet. */ }
    }
    spacing: 16
    Repeater {
        model: root.devices
        ColumnLayout {
            required property var modelData
            Layout.fillWidth: true; spacing: 12
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                ShellIcon { name: "ethernet-port"; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; Layout.fillWidth: true; text: modelData.state; color: root.theme.text; wrapMode: Text.Wrap }
                Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; visible: root.devices.length > 1; text: modelData.name; color: root.theme.secondary }
            }
            Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; text: "Ethernet link  " + (modelData.speed > 0 ? root.speed(modelData.speed) : "—"); color: root.theme.secondary }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true; spacing: 4
        Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; text: "Internet speed"; color: root.theme.secondary }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; Layout.fillWidth: true; text: "↓ " + root.speed(root.result ? root.result.download : null) + "    ↑ " + root.speed(root.result ? root.result.upload : null); color: root.theme.text; elide: Text.ElideRight }
            ShellButton { theme: root.theme; icon: "rotate-cw"; pending: root.testing; enabled: !pending; hint: "Measure internet speed"; onClicked: root.testSpeed() }
        }
        Text {
            font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize
            Layout.fillWidth: true
            text: root.testing ? (root.phase === "upload" ? "Measuring upload…" : "Measuring download…") : root.testError || (root.result ? "Tested " + Qt.formatDateTime(new Date(root.result.measuredAt), "d MMM hh:mm") : "Press refresh to measure")
            color: root.testError && !root.testing ? root.theme.red : root.theme.secondary
            wrapMode: Text.Wrap
        }
    }
    Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; visible: root.unavailable || root.devices.length === 0; text: root.unavailable ? "Connection status unavailable" : reader.running ? "Checking…" : "Ethernet disconnected"; color: root.theme.secondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
    FileView { id: saved; path: root.shell.fixture ? "" : root.resultPath; blockLoading: true; printErrors: false }
    Component.onCompleted: loadResult()
    Process {
        id: reader
        command: ["/usr/bin/python3", root.shell.backend, "ethernet"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const data = JSON.parse(text); if (!data.unavailable) root.update(data); else root.unavailable = true }
                catch (e) { root.unavailable = true }
            }
        }
        onExited: (code, status) => { if (code !== 0) root.unavailable = true }
    }
    Process {
        id: testProcess
        command: ["/usr/bin/python3", root.shell.backend, "speed-test"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    if (data.phase) root.phase = data.phase;
                    if (data.error) root.testError = data.error;
                    if (data.result) { root.result = data.result; root.phase = ""; root.testError = "" }
                } catch (e) { root.testError = "Speed test failed. Try again." }
            }
        }
        onExited: (code, status) => { root.phase = ""; if (code !== 0 && !root.testError) root.testError = "Speed test failed. Try again." }
    }
    Timer {
        id: fixtureTest; interval: 1500
        onTriggered: { root.result = root.shell.fixtureData.internetSpeed || {download: 928.4, upload: 612.7, measuredAt: Date.now()}; root.phase = "" }
    }
    Connections { target: root.shell; function onPanelChanged() { if (root.shell.panel === "ethernet") root.refreshStatus() } }
    Timer { interval: 3000; repeat: true; running: root.shell.panel === "ethernet"; onTriggered: root.refreshStatus() }
}
