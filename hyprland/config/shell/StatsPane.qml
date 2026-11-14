import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    readonly property var stats: shell.stats
    readonly property var snapshot: stats.sample
    property string metric: "cpu"
    property var meterSlots: ({})
    readonly property Item emberTarget: meterSlots[metric] || meterSlots.cpu || null
    function percent(value) { return value === null || value === undefined ? "—" : Math.round(value) + "%"; }
    function detail(key) {
        if (key === "memory") return stats.bytes(snapshot.memoryUsed) + " / " + stats.bytes(snapshot.memoryTotal);
        const temperature = snapshot[key === "cpu" ? "cpuTemperature" : "gpuTemperature"];
        return temperature ? Math.round(temperature) + " °C" : key === "cpu" ? "Processor" : snapshot.gpu == null ? "Unavailable" : "Graphics";
    }
    spacing: 12
    RowLayout {
        Layout.fillWidth: true
        Text { text: "System"; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: 22; Layout.fillWidth: true }
        Text { text: "Utilization · 0–100%"; color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: 14 }
    }
    Repeater {
        model: [{key: "cpu", label: "CPU"}, {key: "memory", label: "Memory"}, {key: "gpu", label: "GPU"}]
        Rectangle {
            id: meter
            required property var modelData
            readonly property var value: root.snapshot[modelData.key]
            Layout.fillWidth: true; implicitHeight: 91; radius: 14; color: root.theme.surface
            activeFocusOnTab: true
            onActiveFocusChanged: { if (activeFocus) root.metric = modelData.key; }
            TapHandler { onTapped: root.metric = meter.modelData.key }
            Component.onCompleted: { const slots = Object.assign({}, root.meterSlots); slots[modelData.key] = valueSlot; root.meterSlots = slots; }
            ColumnLayout {
                anchors { fill: parent; margins: 12 }
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: meter.modelData.label; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: 18 }
                    Text { text: root.detail(meter.modelData.key); color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: 14; Layout.fillWidth: true; elide: Text.ElideRight }
                    Item {
                        implicitWidth: 82; implicitHeight: 38
                        EmberSlot { id: valueSlot; shell: root.shell; anchors.fill: parent; shapeRadius: 12; shapeOpacity: 0.42 }
                        Text { anchors.centerIn: parent; text: root.percent(meter.value); color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: 25 }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; implicitHeight: 6; radius: 3; color: root.theme.background
                    Rectangle { width: parent.width * Math.max(0, Math.min(100, meter.value || 0)) / 100; height: parent.height; radius: 3; color: root.theme.accent; Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
                }
            }
        }
    }
    GridLayout {
        columns: 3; columnSpacing: 18; rowSpacing: 8; Layout.fillWidth: true
        Repeater {
            model: ["↓ " + root.stats.bytes(root.snapshot.down) + "/s", "↑ " + root.stats.bytes(root.snapshot.up) + "/s", "Disk  " + root.percent(root.snapshot.disk), "Swap  " + root.stats.bytes(root.snapshot.swapUsed), "VRAM  " + root.stats.bytes(root.snapshot.vramUsed), "Up  " + (root.snapshot.uptime ? Math.floor(root.snapshot.uptime / 3600) + "h " + Math.floor(root.snapshot.uptime % 3600 / 60) + "m" : "—")]
            Text { required property string modelData; Layout.fillWidth: true; text: modelData; color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: 14 }
        }
    }
    Text { text: root.stats.error; visible: text.length > 0; color: root.theme.red; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize }
    Item { Layout.fillHeight: true }
}
