import QtQuick
import Quickshell
import Quickshell.Bluetooth

Scope {
    id: root
    required property var shell
    readonly property var adapter: shell.fixture ? null : Bluetooth.defaultAdapter
    property bool fixtureEnabled: true
    readonly property bool enabled: shell.fixture ? fixtureEnabled : !!(adapter && adapter.enabled)
    readonly property bool searching: enabled && shell.panel === "bluetooth" && (shell.fixture || !!(adapter && adapter.discovering))
    readonly property var devices: {
        const all = shell.fixture ? fixtureDevices : adapter ? adapter.devices.values : [];
        return all.slice().sort((a, b) => Number(b.connected) - Number(a.connected) || (a.name || a.deviceName || a.address).localeCompare(b.name || b.deviceName || b.address));
    }
    property var fixtureDevices: []
    property var pending: ({})
    property var errors: ({})
    property var scanAdapter: null
    function discover() {
        const wanted = shell.panel === "bluetooth" && enabled;
        if (scanAdapter && (!wanted || scanAdapter !== adapter)) { scanAdapter.discovering = false; scanAdapter = null; }
        if (wanted && adapter && !adapter.discovering) { scanAdapter = adapter; adapter.discovering = true; }
    }
    function togglePower() {
        if (shell.fixture) { fixtureEnabled = !fixtureEnabled; shell.fixtureEvent("bluetooth-power", {enabled: fixtureEnabled}); return; }
        if (adapter) adapter.enabled = !adapter.enabled;
    }
    function busy(device) { return !!pending[device.address] || !!device.pairing || device.state === BluetoothDeviceState.Connecting || device.state === BluetoothDeviceState.Disconnecting; }
    function toggle(device) {
        if (busy(device)) return;
        const next = Object.assign({}, pending);
        next[device.address] = {connect: !device.connected, pairing: !device.connected && !device.paired, started: Date.now()};
        pending = next;
        const clear = Object.assign({}, errors); delete clear[device.address]; errors = clear;
        if (shell.fixture) { shell.fixtureEvent("bluetooth", {address: device.address, connect: !device.connected}); return; }
        if (device.connected) device.disconnect();
        else if (!device.paired) device.pair();
        else device.connect();
    }
    function loadFixture() {
        fixtureEnabled = shell.fixtureData.bluetoothEnabled !== false;
        fixtureDevices = shell.fixtureData.bluetoothDevices || [
            {address: "fixture-headphones", name: "Headphones", connected: true, paired: true},
            {address: "fixture-keyboard", name: "Keyboard", connected: false, paired: true},
            {address: "fixture-speaker", name: "Living room speaker", connected: false, paired: false}
        ];
    }
    Connections { target: root.shell; function onPanelChanged() { root.discover(); } function onFixtureDataChanged() { root.loadFixture(); } }
    onAdapterChanged: discover()
    onEnabledChanged: discover()
    Component.onDestruction: { if (scanAdapter) scanAdapter.discovering = false; }
    Timer {
        interval: 250; repeat: true; running: Object.keys(root.pending).length > 0
        onTriggered: {
            const next = Object.assign({}, root.pending);
            const errors = Object.assign({}, root.errors);
            for (const address of Object.keys(next)) {
                const job = next[address];
                const device = root.devices.find(d => d.address === address);
                if (!device) { delete next[address]; continue; }
                if (root.shell.fixture && Date.now() - job.started > 1200) {
                    root.fixtureDevices = root.fixtureDevices.map(d => d.address === address ? Object.assign({}, d, {connected: job.connect, paired: true}) : d);
                    delete next[address];
                } else if (device.connected === job.connect) delete next[address];
                else if (Date.now() - job.started > 25000) {
                    errors[address] = job.connect ? "Could not connect. Try again." : "Could not disconnect. Try again.";
                    if (job.pairing && device.pairing && !root.shell.fixture) device.cancelPair();
                    delete next[address];
                } else if (job.pairing && device.paired && !root.shell.fixture) { job.pairing = false; device.connect(); }
            }
            root.pending = next; root.errors = errors;
        }
    }
}
