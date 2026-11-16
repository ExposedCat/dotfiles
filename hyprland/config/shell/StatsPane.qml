import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    readonly property var stats: shell.stats
    readonly property var snapshot: stats.sample
    readonly property font valueFont: Qt.font({family: theme.fontFamily, pixelSize: theme.bodySize + 6, weight: theme.fontWeight, features: {"tnum": 1}})
    property string metric: "cpu"
    property var meterSlots: ({})
    readonly property Item emberTarget: meterSlots[metric] || meterSlots.cpu || null
    function percent(value) { return typeof value !== "number" || !Number.isFinite(value) ? "—" : Math.round(value) + "%"; }
    function detail(key) {
        if (key === "memory") return stats.bytes(snapshot.memoryUsed) + " / " + stats.bytes(snapshot.memoryTotal);
        const temperature = snapshot[key === "cpu" ? "cpuTemperature" : "gpuTemperature"];
        const parts = [];
        if (typeof temperature === "number" && Number.isFinite(temperature)) parts.push(Math.round(temperature) + " °C");
        if (key === "gpu" && snapshot.vramUsed != null) parts.push(stats.bytes(snapshot.vramUsed) + (snapshot.vramTotal > 0 ? " / " + stats.bytes(snapshot.vramTotal) : "") + " VRAM");
        return parts.join(" · ") || (key === "cpu" ? "Processor" : snapshot.gpu == null ? "Unavailable" : "Graphics");
    }
    function uptime(seconds) {
        if (typeof seconds !== "number" || !Number.isFinite(seconds)) return "—";
        const minutes = Math.floor(seconds / 60), hours = Math.floor(minutes / 60);
        return (hours >= 24 ? Math.floor(hours / 24) + "d " : "") + hours % 24 + "h " + minutes % 60 + "m";
    }
    spacing: 12
    Repeater {
        model: [{key: "cpu", label: "CPU", icon: "cpu"}, {key: "memory", label: "Memory", icon: "memory-stick"}, {key: "gpu", label: "GPU", icon: "gpu"}]
        ColumnLayout {
            id: meter
            required property var modelData
            readonly property bool gpu: modelData.key === "gpu"
            objectName: "systemMetric:" + modelData.key
            Layout.fillWidth: true
            spacing: 8
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: modelData.label + " " + root.percent(root.snapshot[modelData.key]) + ", " + root.detail(modelData.key)
            onActiveFocusChanged: { if (activeFocus) root.metric = modelData.key; else { history.inspectionIndex = -1; vramHistory.inspectionIndex = -1; } }
            TapHandler { onTapped: { meter.forceActiveFocus(); root.metric = meter.gpu && vramHistory.pointerInside ? "vram" : meter.modelData.key; } }
            Keys.onLeftPressed: (root.metric === "vram" && meter.gpu ? vramHistory : history).moveInspection(-1)
            Keys.onRightPressed: (root.metric === "vram" && meter.gpu ? vramHistory : history).moveInspection(1)
            Component.onCompleted: {
                const slots = Object.assign({}, root.meterSlots);
                slots[modelData.key] = history.emberSlot;
                if (gpu) slots.vram = vramHistory.emberSlot;
                root.meterSlots = slots;
            }
            RowLayout {
                id: metricHeader
                objectName: "systemHeader:" + meter.modelData.key
                Layout.fillWidth: true
                spacing: 12
                ShellIcon { objectName: "systemIcon:" + meter.modelData.key; name: meter.modelData.icon; Layout.preferredWidth: metricText.implicitHeight; Layout.preferredHeight: metricText.implicitHeight }
                ColumnLayout {
                    id: metricText
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    spacing: 0
                    Text { text: meter.modelData.label; color: root.theme.text; font: root.theme.textFont }
                    Text { Layout.fillWidth: true; text: root.detail(meter.modelData.key); color: root.theme.secondary; font: root.theme.textFont; elide: Text.ElideRight }
                }
                Text { objectName: "systemValue:" + meter.modelData.key; text: root.percent(root.snapshot[meter.modelData.key]); color: root.theme.text; font: root.valueFont }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 16
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 1; spacing: 4
                    StatsHistory {
                        id: history
                        Layout.fillWidth: true; Layout.preferredHeight: 52
                        shell: root.shell; theme: root.theme; metric: meter.modelData.key
                        label: meter.modelData.label + (meter.gpu ? " load" : "")
                        samples: root.stats.history; endTime: root.stats.sampleTime
                        value: root.snapshot[meter.modelData.key] ?? null
                        selected: root.metric === metric
                        onHovered: root.metric = metric
                    }
                }
                ColumnLayout {
                    visible: meter.gpu
                    Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 1; spacing: 4
                    StatsHistory {
                        id: vramHistory
                        Layout.fillWidth: true; Layout.preferredHeight: 52
                        shell: root.shell; theme: root.theme; metric: "vram"; label: "VRAM"
                        objectName: meter.gpu ? "systemHistory:vram" : ""
                        samples: root.stats.history; endTime: root.stats.sampleTime
                        value: root.stats.vram; selected: root.metric === metric
                        activeFocusOnTab: meter.gpu
                        onHovered: root.metric = metric
                        onActiveFocusChanged: { if (activeFocus) root.metric = metric; else inspectionIndex = -1; }
                    }
                }
            }
        }
    }
    RowLayout {
        objectName: "systemNetwork"
        Layout.fillWidth: true; Layout.topMargin: 12; spacing: 24
        Repeater {
            model: [{key: "down", label: "Download", icon: "arrow-down"}, {key: "up", label: "Upload", icon: "arrow-up"}]
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 6
                RowLayout {
                    spacing: 8
                    ShellIcon { name: modelData.icon; width: 24; height: 24 }
                    Text { text: modelData.label; font: root.theme.textFont; color: root.theme.secondary }
                }
                Text { Layout.fillWidth: true; text: root.stats.bytes(root.snapshot[modelData.key]) + "/s"; font: root.theme.textFont; color: root.theme.text; elide: Text.ElideRight }
            }
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(root.theme.text, 0.10) }
    RowLayout {
        objectName: "systemFooter"
        Layout.fillWidth: true; spacing: 18
        Repeater {
            model: [{label: "Disk", value: root.percent(root.snapshot.disk) + (root.snapshot.disk == null ? "" : " used")}, {label: "Swap", value: root.stats.bytes(root.snapshot.swapUsed)}, {label: "Up", value: root.uptime(root.snapshot.uptime)}]
            RowLayout {
                required property var modelData
                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 8
                Text { text: modelData.label; color: root.theme.secondary; font: root.theme.textFont }
                Text { Layout.fillWidth: true; text: modelData.value; color: root.theme.text; font: root.theme.textFont; elide: Text.ElideRight }
            }
        }
    }
    Text { Layout.fillWidth: true; text: root.stats.error; visible: text.length > 0; wrapMode: Text.Wrap; color: root.theme.red; font: root.theme.textFont }
}
