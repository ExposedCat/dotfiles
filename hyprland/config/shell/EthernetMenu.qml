import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    property var devices: []
    property Item hoveredButton: null
    property Item focusedButton: null
    property Item interactionButton: null
    function follow(button, pointer, entered) {
        if (pointer) hoveredButton = entered ? button : hoveredButton === button ? null : hoveredButton;
        else focusedButton = entered ? button : focusedButton === button ? null : focusedButton;
        if (entered) interactionButton = button;
        else if (interactionButton === button) interactionButton = hoveredButton || focusedButton;
    }
    readonly property Item emberTarget: {
        const button = interactionButton || hoveredButton || focusedButton;
        if (button && button.visible && (button.enabled || button.pending)) return button.emberSlot;
        if (testing) return measure.emberSlot;
        const count = connections.count;
        for (let i = 0; i < count; i++) if (devices[i].connected) return connections.itemAt(i)?.statusSlot || null;
        return null;
    }
    property bool unavailable: false
    property var result: null
    property string phase: ""
    property string testError: ""
    readonly property bool testing: testProcess.running || fixtureTest.running
    readonly property string resultPath: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/dotfiles/hyprland/internet-speed.json"
    function rateNumber(value) {
        if (value === undefined || value === null) return "—";
        return value >= 1000 ? (value / 1000).toFixed(2) : value.toFixed(1);
    }
    function rateUnit(value) { return value === undefined || value === null ? "" : value >= 1000 ? "Gb/s" : "Mb/s"; }
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
    spacing: 20
    Repeater {
        id: connections
        model: root.unavailable ? [] : root.devices
        RowLayout {
            required property var modelData
            property alias statusSlot: statusSlot
            Layout.fillWidth: true; spacing: 10
            Item {
                implicitWidth: statusLabel.implicitWidth + 20; implicitHeight: 32
                Rectangle { anchors.fill: parent; radius: 16; color: root.theme.surface; visible: !statusSlot.occupied }
                EmberSlot { id: statusSlot; shell: root.shell; anchors.fill: parent; shapeOpacity: 0.45 }
                Text { id: statusLabel; anchors.centerIn: parent; font: root.theme.textFont; text: modelData.state; color: root.theme.text }
            }
            Text { Layout.fillWidth: true; visible: root.devices.length > 1; text: modelData.name; textFormat: Text.PlainText; elide: Text.ElideRight; color: root.theme.secondary; font: root.theme.textFont }
            Item { Layout.fillWidth: true; visible: root.devices.length === 1 }
            Text { font: root.theme.textFont; text: modelData.speed > 0 ? Number(modelData.speed / (modelData.speed >= 1000 ? 1000 : 1)) + (modelData.speed >= 1000 ? " Gb/s link" : " Mb/s link") : ""; color: root.theme.secondary }
        }
    }
    Text { font: root.theme.textFont; visible: root.unavailable || root.devices.length === 0; text: root.unavailable ? "Connection status unavailable" : reader.running ? "Checking…" : "No Ethernet connection"; color: root.theme.secondary; wrapMode: Text.Wrap; Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true; spacing: 24
        Repeater {
            model: [{label: "Download", icon: "arrow-down", key: "download"}, {label: "Upload", icon: "arrow-up", key: "upload"}]
            ColumnLayout {
                id: rate
                required property var modelData
                readonly property var value: root.result ? root.result[modelData.key] : null
                objectName: "network-" + modelData.key
                Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: 0; spacing: 8
                RowLayout {
                    spacing: 6
                    ShellIcon { name: rate.modelData.icon; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
                    Text { text: rate.modelData.label; color: root.theme.secondary; font: root.theme.textFont }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Text { objectName: "network-value-" + rate.modelData.key; text: root.rateNumber(rate.value); color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: 28; font.weight: Font.Medium; font.features: {"tnum": 1}; Layout.alignment: Qt.AlignBaseline }
                    Text { text: root.rateUnit(rate.value); color: root.theme.secondary; font: root.theme.textFont; Layout.alignment: Qt.AlignBaseline }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true; spacing: 12
        Text {
            objectName: "network-test-status"
            font: root.theme.textFont
            Layout.fillWidth: true
            text: root.testing ? (root.phase === "upload" ? "Measuring upload…" : "Measuring download…") : root.testError || (root.result ? "Tested " + Qt.formatDateTime(new Date(root.result.measuredAt), "d MMM, hh:mm") : "No speed test yet")
            color: root.testError && !root.testing ? root.theme.red : root.theme.secondary
            wrapMode: Text.Wrap
        }
        ShellButton {
            id: measure
            objectName: "network-measure"
            theme: root.theme; emberShell: root.shell
            icon: "rotate-cw"; pending: root.testing; enabled: !pending
            hint: "Measure internet speed"; implicitWidth: 40; implicitHeight: 40; radius: 10
            border.width: activeFocus && !root.shell.emberEnabled ? 1 : 0
            onHoveredChanged: root.follow(this, true, hovered)
            onActiveFocusChanged: root.follow(this, false, activeFocus)
            onClicked: root.testSpeed()
        }
    }
    FileView { id: saved; path: root.shell.fixture ? "" : root.resultPath; blockLoading: true; printErrors: false }
    Component.onCompleted: { loadResult(); if (shell.panel === "ethernet") refreshStatus(); }
    Process {
        id: reader
        command: [root.shell.backend, "shell", "ethernet"]
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
        command: [root.shell.backend, "shell", "speed-test"]
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
