import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    property var focusedSlider: null
    readonly property Item emberTarget: (focusedSlider || volume).enabled ? (focusedSlider || volume).emberSlot : null
    readonly property var audio: shell.audio
    property var monitorData: ({})
    ListModel { id: monitorModel }
    function syncMonitors() {
        const devices = shell.brightness.devices, data = {};
        for (const device of devices) data[device.name] = device;
        monitorData = data;
        const names = devices.map(d => d.name);
        for (let i = monitorModel.count - 1; i >= 0; i--) if (!names.includes(monitorModel.get(i).outputName)) monitorModel.remove(i);
        for (let i = 0; i < names.length; i++) {
            let at = -1;
            for (let j = i; j < monitorModel.count; j++) if (monitorModel.get(j).outputName === names[i]) { at = j; break; }
            if (at < 0) monitorModel.insert(i, {outputName: names[i]});
            else if (at !== i) monitorModel.move(at, i, 1);
        }
    }
    Component.onCompleted: syncMonitors()
    Connections { target: root.shell.brightness; function onDevicesChanged() { root.syncMonitors(); } }
    spacing: 12
    function follow(slider) { focusedSlider = slider; }
    RowLayout {
        Layout.fillWidth: true
        Text { text: "Sound & brightness"; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: 22; Layout.fillWidth: true }
        ShellButton { theme: root.theme; icon: root.audio.muted ? "volume-x" : "volume-2"; hint: "Mute output"; selected: root.audio.muted; onClicked: root.audio.toggleMute() }
        ShellButton { theme: root.theme; icon: root.audio.micMuted ? "mic-off" : "mic"; hint: "Mute microphone"; selected: root.audio.micMuted; onClicked: root.audio.toggleMicMute() }
    }
    PillComboBox {
        theme: root.theme
        Layout.fillWidth: true; model: root.audio.outputs.map(n => n.description || n.name)
        currentIndex: Math.max(0, root.audio.outputs.indexOf(root.audio.sink)); enabled: count > 0
        onActivated: root.audio.selectDevice(currentIndex, false)
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; Accessible.name: "Audio output"
    }
    RowLayout {
        Layout.fillWidth: true
        PillSlider { id: volume; emberShell: root.shell; onHoveredChanged: { if (hovered) root.follow(this); } onActiveFocusChanged: { if (activeFocus) root.follow(this); } theme: root.theme; Layout.fillWidth: true; backendValue: root.audio.volume; enabled: root.audio.available; onMoved: { root.audio.setVolume(value, false); root.follow(this); } Accessible.name: "Output volume" }
        Text { text: Math.round(volume.value * 100) + "%"; color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; Layout.preferredWidth: 50 }
    }
    PillComboBox {
        theme: root.theme
        Layout.fillWidth: true; model: root.audio.inputs.map(n => n.description || n.name)
        currentIndex: Math.max(0, root.audio.inputs.indexOf(root.audio.source)); enabled: count > 0
        onActivated: root.audio.selectDevice(currentIndex, true)
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; Accessible.name: "Microphone input"
    }
    RowLayout {
        Layout.fillWidth: true
        PillSlider { id: mic; emberShell: root.shell; onHoveredChanged: { if (hovered) root.follow(this); } onActiveFocusChanged: { if (activeFocus) root.follow(this); } theme: root.theme; Layout.fillWidth: true; backendValue: root.audio.micVolume; enabled: root.shell.fixture || !!root.audio.source; onMoved: { root.audio.setVolume(value, true); root.follow(this); } Accessible.name: "Microphone volume" }
        Text { text: Math.round(mic.value * 100) + "%"; color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; Layout.preferredWidth: 50 }
    }
    Text { text: root.shell.brightness.loading ? "Reading monitors…" : "Monitor brightness"; color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize }
    Repeater {
        model: monitorModel
        ColumnLayout {
            required property string outputName
            readonly property var modelData: root.monitorData[outputName] || ({name:outputName,description:outputName,level:0,supported:false})
            Layout.fillWidth: true; spacing: 2
            Text { Layout.fillWidth: true; text: modelData.description; textFormat: Text.PlainText; color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; elide: Text.ElideRight }
            RowLayout {
                Layout.fillWidth: true
                PillSlider {
                    id: light; emberShell: root.shell
                    onHoveredChanged: { if (hovered) root.follow(this); }
                    onActiveFocusChanged: { if (activeFocus) root.follow(this); } Layout.fillWidth: true; theme: root.theme; backendValue: modelData.level; enabled: modelData.supported
                    onMoved: { commit.restart(); root.follow(this); }
                    onPressedChanged: { if (!pressed && enabled && commit.running) { commit.stop(); root.shell.brightness.setLevel(modelData.name, value); } }
                    Timer { id: commit; interval: 200; onTriggered: root.shell.brightness.setLevel(modelData.name, light.value) }
                    Accessible.name: modelData.description + " brightness"
                }
                Text { text: modelData.supported ? Math.round(light.value * 100) + "%" : "—"; color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; Layout.preferredWidth: 50 }
            }
        }
    }
    Text { text: root.shell.brightness.error || (root.shell.brightness.busy ? "Applying brightness…" : ""); visible: text.length > 0; color: root.shell.brightness.error ? root.theme.red : root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize }
    Item { Layout.fillHeight: true }
}
