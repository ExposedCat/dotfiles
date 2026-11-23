import QtQuick
import QtQuick.Layouts

Flickable {
    id: root
    required property var shell
    required property var theme
    property var focusedSlider: null
    property string devicePicker: ""
    readonly property var currentSlider: focusedSlider || volume.slider
    readonly property Item emberTarget: currentSlider.enabled && !currentSlider.muted && currentSlider.position > 0 ? currentSlider.emberSlot : null
    readonly property var audio: shell.audio
    implicitHeight: channels.implicitHeight
    contentWidth: width
    contentHeight: channels.implicitHeight
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    PillWheel { flickable: root }

    function follow(slider) { focusedSlider = slider; }

    function toggleDevicePicker(name) { devicePicker = devicePicker === name ? "" : name; }

    function closeDevicePicker() {
        if (!devicePicker) return false;
        devicePicker = "";
        return true;
    }

    Connections {
        target: root.shell
        function onPanelChanged() { if (root.shell.panel !== "mixer") root.closeDevicePicker(); }
        function onPillHiddenChanged() { if (root.shell.pillHidden) root.closeDevicePicker(); }
    }

    ColumnLayout {
        id: channels
        width: root.width; spacing: root.theme.overviewGap
        MixerFader {
            id: volume
            Layout.fillWidth: true; Layout.minimumWidth: 0
            shell: root.shell; theme: root.theme
            controlId: "Output"; selectorName: "audioOutput"; hint: "Output volume"
            icon: root.audio.muted ? "volume-x" : "volume-2"
            muted: root.audio.muted
            backendValue: root.audio.volume; available: root.audio.available
            devices: root.audio.outputs.map(n => n.description || n.name)
            selectedDevice: root.audio.outputs.indexOf(root.audio.sink)
            devicesExpanded: root.devicePicker === selectorName
            onDevicePickerRequested: root.toggleDevicePicker(selectorName)
            onDeviceSelected: index => { root.audio.selectDevice(index, false); root.closeDevicePicker(); }
            onToggleRequested: root.audio.toggleMute()
            onFocused: slider => root.follow(slider)
            onMoved: value => root.audio.setVolume(value, false)
        }
        MixerFader {
            id: mic
            Layout.fillWidth: true; Layout.minimumWidth: 0
            shell: root.shell; theme: root.theme
            controlId: "Input"; selectorName: "audioInput"; hint: "Microphone volume"
            icon: root.audio.micMuted ? "mic-off" : "mic"
            muted: root.audio.micMuted
            backendValue: root.audio.micVolume
            available: root.shell.fixture || !!(root.audio.source && root.audio.source.ready && root.audio.source.audio)
            devices: root.audio.inputs.map(n => n.description || n.name)
            selectedDevice: root.audio.inputs.indexOf(root.audio.source)
            devicesExpanded: root.devicePicker === selectorName
            onDevicePickerRequested: root.toggleDevicePicker(selectorName)
            onDeviceSelected: index => { root.audio.selectDevice(index, true); root.closeDevicePicker(); }
            onToggleRequested: root.audio.toggleMicMute()
            onFocused: slider => root.follow(slider)
            onMoved: value => root.audio.setVolume(value, true)
        }
    }
}
