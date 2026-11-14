import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    readonly property var bluetooth: shell.bluetooth
    property Item hoveredDevice: null
    property Item focusedDevice: null
    readonly property Item emberTarget: (hoveredDevice || focusedDevice)?.emberSlot || powerSlot
    property var deviceData: ({})
    function syncDevices() {
        const devices = bluetooth.enabled ? bluetooth.devices : [];
        const data = Object.assign({}, deviceData);
        for (const device of devices) data[device.address] = device;
        deviceData = data;
        const keys = devices.map(d => d.address);
        for (let i = deviceModel.count - 1; i >= 0; --i) if (!keys.includes(deviceModel.get(i).address)) deviceModel.remove(i);
        for (let i = 0; i < keys.length; ++i) {
            let at = -1;
            for (let j = i; j < deviceModel.count; ++j) if (deviceModel.get(j).address === keys[i]) { at = j; break }
            if (at < 0) deviceModel.insert(i, {address: keys[i]});
            else if (at !== i) deviceModel.move(at, i, 1);
        }
    }
    ListModel { id: deviceModel }
    Connections { target: root.bluetooth; function onDevicesChanged() { root.syncDevices() } function onEnabledChanged() { root.syncDevices() } }
    Component.onCompleted: syncDevices()
    spacing: 12
    RowLayout {
        Layout.fillWidth: true
        Spinner { running: root.bluetooth.searching; visible: running; Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
        Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; Layout.fillWidth: true; text: root.bluetooth.searching ? "Searching…" : root.bluetooth.enabled ? "" : "Bluetooth off"; color: root.theme.secondary }
        Switch {
            id: powerSwitch
            checked: root.bluetooth.enabled
            enabled: root.shell.fixture || !!root.bluetooth.adapter
            Accessible.name: "Bluetooth power"
            onToggled: { if (checked !== root.bluetooth.enabled) root.bluetooth.togglePower(); }
            indicator: Rectangle {
                implicitWidth: 46; implicitHeight: 26; radius: 13; color: root.theme.surface
                x: powerSwitch.leftPadding; y: Math.round((powerSwitch.height - height) / 2)
                Item {
                    x: powerSwitch.checked ? 23 : 3; y: 3; width: 20; height: 20
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.InOutCubic } }
                    Rectangle { anchors.fill: parent; radius: 10; color: root.theme.secondary; visible: !powerSlot.occupied }
                    EmberSlot { id: powerSlot; shell: root.shell; anchors.fill: parent }
                }
            }
            contentItem: Text { text: "Bluetooth"; leftPadding: powerSwitch.indicator.width + powerSwitch.spacing; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; verticalAlignment: Text.AlignVCenter }
        }
    }
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        clip: true; spacing: 6
        model: deviceModel
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        delegate: ColumnLayout {
            id: deviceRow
            required property string address
            readonly property var modelData: root.deviceData[address] || ({address: address, name: address, connected: false})
            required property int index
            width: list.width
            spacing: 6
            Rectangle {
                visible: deviceRow.index > 0 && !deviceRow.modelData.connected && root.bluetooth.devices[deviceRow.index - 1].connected
                Layout.fillWidth: true; implicitHeight: 1; Layout.topMargin: 8; Layout.bottomMargin: 8
                color: root.theme.surface
            }
            ShellButton {
                emberShell: root.shell
                onHoveredChanged: { if (hovered) root.hoveredDevice = this; else if (root.hoveredDevice === this) root.hoveredDevice = null; }
                onActiveFocusChanged: { if (activeFocus) root.focusedDevice = this; else if (root.focusedDevice === this) root.focusedDevice = null; }
                theme: root.theme
                Layout.fillWidth: true; implicitHeight: 54
                icon: deviceRow.modelData.connected ? "check" : "bluetooth"
                elideText: true
                text: deviceRow.modelData.name || deviceRow.modelData.deviceName || deviceRow.modelData.address
                hint: (deviceRow.modelData.connected ? "Disconnect " : "Connect to ") + text
                selected: !!deviceRow.modelData.connected
                pending: root.bluetooth.busy(deviceRow.modelData)
                enabled: !pending && !!root.deviceData[deviceRow.address]
                onClicked: root.bluetooth.toggle(deviceRow.modelData)
            }
            Text {
                font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize
                Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                text: root.bluetooth.errors[deviceRow.modelData.address] || ""
                visible: text.length > 0; wrapMode: Text.Wrap
                color: root.theme.red;
            }
        }
    }
    Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; visible: root.bluetooth.enabled && list.count === 0; text: "No devices found"; color: root.theme.secondary }
}
