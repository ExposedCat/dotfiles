import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var shell
    required property var theme
    property var focusedSlider: null
    readonly property Item emberTarget: (focusedSlider || volume.slider).enabled ? (focusedSlider || volume.slider).emberSlot : null
    readonly property var audio: shell.audio
    implicitHeight: 200
    function follow(slider) { focusedSlider = slider; }
    RowLayout {
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
        width: Math.min(parent.width, 472); height: 200; spacing: 32
        MixerFader {
            id: volume
            Layout.fillWidth: true; Layout.preferredWidth: 220; Layout.minimumWidth: 0; Layout.maximumWidth: Infinity; Layout.preferredHeight: 200
            shell: root.shell; theme: root.theme
            controlId: "Output"; selectorName: "audioOutput"; hint: "Output volume"
            icon: root.audio.muted ? "volume-x" : "volume-2"
            muted: root.audio.muted
            backendValue: root.audio.volume; available: root.audio.available
            devices: root.audio.outputs.map(n => n.description || n.name)
            selectedDevice: Math.max(0, root.audio.outputs.indexOf(root.audio.sink))
            onDeviceSelected: index => root.audio.selectDevice(index, false)
            onToggleRequested: root.audio.toggleMute()
            onFocused: slider => root.follow(slider)
            onMoved: value => root.audio.setVolume(value, false)
        }
        MixerFader {
            id: mic
            Layout.fillWidth: true; Layout.preferredWidth: 220; Layout.minimumWidth: 0; Layout.maximumWidth: Infinity; Layout.preferredHeight: 200
            shell: root.shell; theme: root.theme
            controlId: "Input"; selectorName: "audioInput"; hint: "Microphone volume"
            icon: root.audio.micMuted ? "mic-off" : "mic"
            muted: root.audio.micMuted
            backendValue: root.audio.micVolume
            available: root.shell.fixture || !!(root.audio.source && root.audio.source.ready && root.audio.source.audio)
            devices: root.audio.inputs.map(n => n.description || n.name)
            selectedDevice: Math.max(0, root.audio.inputs.indexOf(root.audio.source))
            onDeviceSelected: index => root.audio.selectDevice(index, true)
            onToggleRequested: root.audio.toggleMicMute()
            onFocused: slider => root.follow(slider)
            onMoved: value => root.audio.setVolume(value, true)
        }
    }
}
