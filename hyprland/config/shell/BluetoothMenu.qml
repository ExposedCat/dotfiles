import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    readonly property var bluetooth: shell.bluetooth
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
        ShellButton { theme: root.theme; icon: "power"; selected: root.bluetooth.enabled; hint: root.bluetooth.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"; enabled: root.shell.fixture || !!root.bluetooth.adapter; onClicked: root.bluetooth.togglePower() }
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
            readonly property var modelData: root.deviceData[address]
            required property int index
            width: list.width
            spacing: 6
            Rectangle {
                visible: deviceRow.index > 0 && !deviceRow.modelData.connected && root.bluetooth.devices[deviceRow.index - 1].connected
                Layout.fillWidth: true; implicitHeight: 1; Layout.topMargin: 8; Layout.bottomMargin: 8
                color: root.theme.surface
            }
            ShellButton {
                theme: root.theme
                Layout.fillWidth: true; implicitHeight: 54
                icon: deviceRow.modelData.connected ? "check" : "bluetooth"
                elideText: true
                text: deviceRow.modelData.name || deviceRow.modelData.deviceName || deviceRow.modelData.address
                hint: (deviceRow.modelData.connected ? "Disconnect " : "Connect to ") + text
                selected: !!deviceRow.modelData.connected
                pending: root.bluetooth.busy(deviceRow.modelData)
                enabled: !pending
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
