import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: root
    required property var shell
    required property var theme
    property string icon: "volume-2"
    property string controlId: ""
    property string selectorName: ""
    property string hint: ""
    property real backendValue: 0
    property bool available: true
    property bool muted: false
    property var devices: []
    property int selectedDevice: 0
    property alias slider: fader
    signal moved(real value)
    signal released(real value)
    signal focused(var slider)
    signal toggleRequested()
    signal deviceSelected(int index)
    implicitWidth: 472; implicitHeight: 40
    function openDevices() {
        if (!devices.length) return;
        deviceChoice.forceActiveFocus();
        deviceChoice.popup.open();
    }
    spacing: 12
    Item {
        Layout.preferredWidth: 36; Layout.preferredHeight: 36
        // Keep the standard picker behavior, with its visual field replaced by
        // the mute icon. Device names appear only in the open dropdown.
        PillComboBox {
            id: deviceChoice
            anchors.fill: parent
            objectName: root.selectorName
            theme: root.theme; flat: true; menuWidth: 420
            model: root.devices; currentIndex: root.selectedDevice; enabled: count > 0
            focusPolicy: Qt.NoFocus
            background: Item {}
            contentItem: Item {}
            indicator: Item {}
            Accessible.ignored: true
            onActivated: root.deviceSelected(currentIndex)
        }
        ShellButton {
            id: toggleButton
            objectName: "audioIcon:" + root.controlId
            anchors.fill: parent; enabled: root.available || root.devices.length > 0
            theme: root.theme; icon: root.icon
            hint: root.hint + (root.muted ? " · unmute" : " · mute") + "; right-click to choose device"
            selected: root.muted
            mouseButtons: Qt.LeftButton | Qt.RightButton
            onClicked: button => {
                if (button === Qt.RightButton) root.openDevices();
                else if (root.available) root.toggleRequested();
            }
            Keys.onMenuPressed: root.openDevices()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)) { root.openDevices(); event.accepted = true; }
            }
        }
        Connections {
            target: deviceChoice.popup
            function onClosed() { if (root.visible && root.shell.panel === "mixer" && !root.shell.pillHidden) toggleButton.forceActiveFocus(); }
        }
        Connections {
            target: root.shell
            function onPanelChanged() { if (root.shell.panel !== "mixer") deviceChoice.popup.close(); }
            function onPillHiddenChanged() { if (root.shell.pillHidden) deviceChoice.popup.close(); }
        }
    }
    PillSlider {
        id: fader
        objectName: "fader:" + root.controlId
        Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredHeight: 40
        theme: root.theme; emberShell: root.shell
        orientation: Qt.Horizontal; thickTrack: true; muted: root.muted
        backendValue: root.backendValue; enabled: root.available
        wheelEnabled: true
        onMoved: { root.focused(this); root.moved(value); }
        onHoveredChanged: { if (hovered) root.focused(this); }
        onActiveFocusChanged: { if (activeFocus) root.focused(this); }
        onPressedChanged: { if (pressed) root.focused(this); else root.released(value); }
        Accessible.name: root.hint
    }
    Text {
        Layout.preferredWidth: 44
        horizontalAlignment: Text.AlignRight
        text: root.available ? Math.round(fader.value * 100) + "%" : "—"
        color: root.theme.text; opacity: root.shell.emberTarget === fader.emberSlot ? 1 : 0.75
        font: root.theme.textFont
    }
}
