import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

Scope {
    id: test
    property var app: null
    property int openingFrames: 0
    property int closingFrames: 0
    property int emberFrames: 0
    property real previousHeight: 40
    property bool watchBluetoothFlow: false
    property real flowMinHeight: 10000
    property var flowPanels: []
    function all(item) { let found = []; for (const child of item?.children || []) { found.push(child); found = found.concat(all(child)); } return found; }
    function named(name) { return all(app.pill.activePane).find(item => item.objectName === name); }
    TestResult { id: objects }
    Component.onCompleted: {
        if (!Quickshell.env("DOTFILES_SHELL_FIXTURE")) throw Error("Private fixture required");
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        if (component.status !== Component.Ready) throw Error(component.errorString());
        app = component.createObject(test);
        if (!app) throw Error(component.errorString());
    }
    Timer {
        interval: 16; running: !!test.app; repeat: true
        onTriggered: {
            if (test.app.pill.ember.moving) test.emberFrames++;
            const height = test.app.pill.pillGeometry.height;
            if (test.watchBluetoothFlow) {
                test.flowMinHeight = Math.min(test.flowMinHeight, height);
                if (test.flowPanels[test.flowPanels.length - 1] !== test.app.panel) test.flowPanels = test.flowPanels.concat([test.app.panel]);
            }
            if (height !== test.previousHeight && height > 40) {
                if (test.app.panel === "credentials") test.openingFrames++;
                else test.closingFrames++;
            }
            test.previousHeight = height;
        }
    }
    IpcHandler {
        target: "credentialTest"
        function state(): string {
            if (!test.app) return "{}";
            const list = test.named("bluetooth-devices"), rows = [];
            if (list) for (let i = 0; i < list.count; ++i) { const item = list.itemAtIndex(i); if (item) rows.push({address: item.address, remembered: item.remembered, pending: item.pending}); }
            return JSON.stringify({panel: test.app.panel, active: test.app.credentials.active,
                kind: test.app.credentials.data.kind || "", code: test.app.credentials.data.code || "",
                fields: (test.app.credentials.data.fields || []).length,
                width: test.app.pill.pillGeometry.width, height: test.app.pill.pillGeometry.height,
                opening: test.openingFrames, closing: test.closingFrames,
                heading: test.app.pill.activePane?.heading || "", icon: test.app.pill.activePane?.headingIcon || "",
                body: test.app.credentials.data.body || "",
                ember: test.app.pill.ember.target?.objectName || "",
                dock: test.app.pill.ember.dock?.objectName || "", emberFrames: test.emberFrames,
                btRows: rows, btSelected: test.app.pill.activePane?.selectedAddress || "", btSearching: test.app.bluetooth.searching,
                btPending: Object.keys(test.app.bluetooth.pending), btEnabled: test.app.bluetooth.enabled,
                flowMinHeight: test.flowMinHeight, flowPanels: test.flowPanels,
                paneHeight: test.app.pill.activePane?.height, contentHeight: test.app.pill.activePane?.implicitHeight,
                canAccept: !!test.app.pill.activePane?.canAccept});
        }
        function fill(index: int, value: string): void {
            test.app.pill.activePane.setInput(index, value);
        }
        function accept(): void { test.app.pill.activePane.accept(); }
        function inputPoint(index: int): string { return JSON.stringify(test.app.pill.activePane.inputPoint(index)); }
        function controlPoint(name: string, index: int): string { return JSON.stringify(test.app.pill.activePane.controlPoint(name, index)); }
        function revealed(index: int): bool { return test.app.pill.activePane.inputRevealed(index); }
        function cancel(): void { test.app.pill.dismiss(); }
        function bluetooth(): void {
            test.app.fixtureData = Object.assign({}, test.app.fixtureData, {bluetoothManualPairing: true, bluetoothDevices: [
                {address: "headphones", name: "Headphones", icon: "audio-headphones", paired: true, connected: true},
                {address: "mouse", name: "MX Master 3", icon: "input-mouse", paired: true, connected: false},
                {address: "AA:BB:CC:DD:EE:FF", dbusPath: "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF", name: "Keychron K2", icon: "input-keyboard", paired: false, connected: false}
            ]});
            test.app.toggle("bluetooth");
        }
        function bluetoothPoint(address: string): string {
            const rows = test.app.pill.activePane.rowItems;
            if (address === "gap") { const row = rows.headphones; return JSON.stringify(row.mapToGlobal(row.width / 2, row.height + 3)); }
            const row = rows[address]; return JSON.stringify(row.mapToGlobal(row.width / 2, row.height / 2));
        }
        function bluetoothFocus(address: string): void { test.app.pill.activePane.rowItems[address].forceActiveFocus(); }
        function bluetoothChurn(): void { test.app.bluetooth.fixtureDevices = test.app.bluetooth.fixtureDevices.concat([{address: "new", name: "AAA new speaker", icon: "audio-card", paired: false, connected: false}]); }
        function bluetoothComplete(): void { test.app.bluetooth.fixtureDevices = test.app.bluetooth.fixtureDevices.map(d => d.address === "AA:BB:CC:DD:EE:FF" ? Object.assign({}, d, {paired: true, connected: true}) : d); }
        function bluetoothUnpair(): void { test.app.bluetooth.fixtureDevices = test.app.bluetooth.fixtureDevices.filter(d => d.address !== "new").map(d => d.address === "AA:BB:CC:DD:EE:FF" ? Object.assign({}, d, {paired: false, connected: false}) : d); }
        function bluetoothPower(): void { test.app.bluetooth.togglePower(); }
        function bluetoothFlow(): void { test.flowMinHeight = test.app.pill.pillGeometry.height; test.flowPanels = [test.app.panel]; test.watchBluetoothFlow = true; }
        function stopBluetoothFlow(): void { test.watchBluetoothFlow = false; }
    }
}
