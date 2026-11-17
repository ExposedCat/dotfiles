import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    readonly property var bluetooth: shell.bluetooth
    property string selectedAddress: ""
    property bool powerSelected: false
    property var rowItems: ({})
    property var deviceData: ({})
    readonly property var deviceSnapshot: bluetooth.devices.map(device => ({
        device: device, address: device.address,
        remembered: !!(device.paired || device.bonded || device.connected)
    }))
    readonly property Item emberTarget: powerSelected ? powerSlot : rowItems[selectedAddress]?.emberSlot || null
    function selectDevice(address) { selectedAddress = address; powerSelected = false; }
    function followPointer() {
        // Follow actual pointer movement, not hover events synthesized when
        // the pairing prompt morphs back into a row beneath a stationary mouse.
        const position = shell.pill.pointerPosition;
        const power = powerSwitch.mapFromItem(shell.pill.contentItem, position.x, position.y);
        if (powerSwitch.enabled && power.x >= 0 && power.y >= 0 && power.x < powerSwitch.width && power.y < powerSwitch.height) { powerSelected = true; return; }
        for (const address of Object.keys(rowItems)) {
            const row = rowItems[address];
            if (!row.visible || !row.enabled) continue;
            const point = row.mapFromItem(shell.pill.contentItem, position.x, position.y);
            if (point.x >= 0 && point.y >= 0 && point.x < row.width && point.y < row.height) { selectDevice(address); return; }
        }
    }
    function deviceIcon(device) {
        const icon = device.icon || "";
        if (icon.includes("head")) return "headphones";
        if (icon.includes("keyboard")) return "keyboard";
        if (icon.includes("mouse")) return "mouse";
        if (icon.includes("audio")) return "speaker";
        return "bluetooth";
    }
    function restoreFocus() {
        if (powerSelected) powerSwitch.forceActiveFocus();
        else if (rowItems[selectedAddress]?.enabled) rowItems[selectedAddress].forceActiveFocus();
        else root.forceActiveFocus();
    }
    function syncDevices() {
        const devices = deviceSnapshot.filter(item => bluetooth.enabled || item.remembered);
        const data = {}, remembered = {};
        for (const item of devices) { data[item.address] = item.device; remembered[item.address] = item.remembered; }
        deviceData = data;
        // Keep existing order within each section while discovery and state
        // updates arrive. A newly paired device joins the remembered section.
        let keys = [];
        for (let i = 0; i < deviceModel.count; ++i) {
            const address = deviceModel.get(i).address;
            if (data[address]) keys.push(address);
        }
        for (const item of devices) if (!keys.includes(item.address)) keys.push(item.address);
        keys = keys.filter(address => remembered[address]).concat(keys.filter(address => !remembered[address]));
        for (let i = deviceModel.count - 1; i >= 0; --i) if (!keys.includes(deviceModel.get(i).address)) deviceModel.remove(i);
        for (let i = 0; i < keys.length; ++i) {
            let at = -1;
            for (let j = i; j < deviceModel.count; ++j) if (deviceModel.get(j).address === keys[i]) { at = j; break; }
            if (at < 0) deviceModel.insert(i, {address: keys[i], remembered: remembered[keys[i]]});
            else {
                if (at !== i) deviceModel.move(at, i, 1);
                deviceModel.setProperty(i, "remembered", remembered[keys[i]]);
            }
        }
        if (!keys.includes(selectedAddress)) selectedAddress = keys.find(address => data[address].connected) || keys[0] || "";
    }
    onDeviceSnapshotChanged: Qt.callLater(syncDevices)
    ListModel { id: deviceModel }
    Connections { target: root.bluetooth; function onEnabledChanged() { Qt.callLater(root.syncDevices); } }
    Connections { target: root.shell; function onPanelChanged() { if (root.shell.panel === "bluetooth") Qt.callLater(root.restoreFocus); } }
    Connections { target: root.shell.pill; function onPointerPositionChanged() { if (root.shell.panel === "bluetooth") root.followPointer(); } }
    Component.onCompleted: syncDevices()
    spacing: 20
    RowLayout {
        Layout.fillWidth: true; spacing: 10
        ShellIcon { objectName: "bluetooth-header-icon"; name: root.bluetooth.enabled ? "bluetooth" : "bluetooth-off"; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
        Text { text: "Bluetooth"; color: root.theme.text; font: root.theme.textFont; Layout.fillWidth: true }
        Spinner { running: root.bluetooth.searching; visible: running; Layout.preferredWidth: 16; Layout.preferredHeight: 16 }
        Switch {
            id: powerSwitch
            objectName: "bluetooth-power"
            implicitWidth: 46; implicitHeight: 30; padding: 0
            hoverEnabled: true
            checked: root.bluetooth.enabled
            enabled: root.shell.fixture || !!root.bluetooth.adapter
            Accessible.name: "Bluetooth power"
            onActiveFocusChanged: { if (activeFocus) root.powerSelected = true; }
            onToggled: { root.powerSelected = true; if (checked !== root.bluetooth.enabled) root.bluetooth.togglePower(); }
            indicator: Rectangle {
                implicitWidth: 46; implicitHeight: 26; radius: 13; color: root.theme.surface
                y: Math.round((powerSwitch.height - height) / 2)
                Item {
                    x: powerSwitch.checked ? 23 : 3; y: 3; width: 20; height: 20
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.InOutCubic } }
                    Rectangle { anchors.fill: parent; radius: 10; color: root.theme.secondary; visible: !powerSlot.occupied }
                    EmberSlot { id: powerSlot; objectName: "bluetooth-power-slot"; shell: root.shell; anchors.fill: parent }
                }
            }
            contentItem: Item {}
        }
    }
    ListView {
        id: list
        objectName: "bluetooth-devices"
        Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0
        implicitHeight: Math.min(380, contentHeight)
        clip: true; spacing: 6
        model: deviceModel
        boundsBehavior: Flickable.StopAtBounds
        move: Transition { NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic } }
        displaced: Transition { NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic } }
        PillWheel { flickable: list }
        ScrollBar.vertical: ScrollBar {}
        delegate: ColumnLayout {
            id: deviceRow
            required property string address
            required property bool remembered
            required property int index
            readonly property var device: root.deviceData[address] || ({address: address, name: address, connected: false})
            readonly property bool pending: root.bluetooth.busy(device)
            width: list.width; height: implicitHeight; spacing: 0
            Rectangle {
                objectName: "bluetooth-divider"
                visible: deviceRow.index > 0 && !deviceRow.remembered && !!deviceModel.get(deviceRow.index - 1)?.remembered
                Layout.fillWidth: true; implicitHeight: 1; Layout.topMargin: 10; Layout.bottomMargin: 10
                color: Qt.alpha(root.theme.text, 0.10)
            }
            Rectangle {
                id: button
                objectName: "bluetooth-device:" + deviceRow.address
                property alias emberSlot: deviceSlot
                readonly property string hint: (deviceRow.device.connected ? "Disconnect " : "Connect to ") + label.text
                Layout.fillWidth: true; implicitHeight: 48; radius: 10
                color: "transparent"
                opacity: root.bluetooth.enabled ? 1 : 0.45
                enabled: root.bluetooth.enabled && !deviceRow.pending && !!root.deviceData[deviceRow.address]
                activeFocusOnTab: true
                border.width: activeFocus && !root.shell.emberEnabled ? 1 : 0
                border.color: root.theme.accent
                Accessible.role: Accessible.Button
                Accessible.name: hint
                Accessible.description: deviceRow.pending ? (root.bluetooth.pending[deviceRow.address]?.connect === false ? "Disconnecting" : "Connecting") : deviceRow.device.connected ? "Connected" : deviceRow.remembered ? "Paired device" : "Nearby device, pair and connect"
                function activate() { root.selectDevice(deviceRow.address); root.bluetooth.toggle(deviceRow.device); }
                Accessible.onPressAction: activate()
                Keys.onReturnPressed: activate()
                Keys.onSpacePressed: activate()
                onActiveFocusChanged: { if (activeFocus) root.selectDevice(deviceRow.address); }
                Component.onCompleted: { const items = Object.assign({}, root.rowItems); items[deviceRow.address] = button; root.rowItems = items; }
                Component.onDestruction: {
                    if (root.rowItems[deviceRow.address] === button) { const items = Object.assign({}, root.rowItems); delete items[deviceRow.address]; root.rowItems = items; }
                }
                EmberSlot { id: deviceSlot; objectName: "bluetooth-row:" + deviceRow.address; shell: root.shell; anchors.fill: parent; shapeRadius: 10; shapeOpacity: 0.42 }
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 12
                    ShellIcon { name: root.deviceIcon(deviceRow.device); Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                    Text { id: label; Layout.fillWidth: true; Layout.minimumWidth: 0; text: deviceRow.device.name || deviceRow.device.deviceName || deviceRow.address; textFormat: Text.PlainText; elide: Text.ElideRight; color: root.theme.text; font: root.theme.textFont }
                    Spinner { objectName: "bluetooth-pending:" + deviceRow.address; running: deviceRow.pending; visible: running; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                    ShellIcon { objectName: "bluetooth-connected:" + deviceRow.address; name: "bluetooth-connected"; visible: root.bluetooth.enabled && !!deviceRow.device.connected && !deviceRow.pending; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { button.forceActiveFocus(Qt.MouseFocusReason); button.activate(); } }
            }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 6
                text: root.bluetooth.errors[deviceRow.address] || ""; visible: text.length > 0
                wrapMode: Text.Wrap; color: root.theme.red; font: root.theme.textFont
            }
        }
    }
    Text {
        Layout.fillWidth: true; font: root.theme.textFont; color: root.theme.secondary; wrapMode: Text.Wrap
        visible: (!root.shell.fixture && !root.bluetooth.adapter) || (root.bluetooth.enabled && list.count === 0)
        text: !root.shell.fixture && !root.bluetooth.adapter ? "Bluetooth unavailable" : "No devices found"
    }
}
