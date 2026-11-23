import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
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
    property int selectedDevice: -1
    property bool devicesExpanded: false
    property Item deviceTrigger: null
    property alias slider: fader
    signal moved(real value)
    signal released(real value)
    signal focused(var slider)
    signal toggleRequested()
    signal devicePickerRequested()
    signal deviceSelected(int index)

    readonly property int buttonSize: theme.overviewControlSize
    readonly property int channelPadding: theme.overviewControlPadding
    implicitWidth: controls.implicitWidth + 2 * channelPadding
    implicitHeight: buttonSize + 2 * channelPadding
        + (devicesExpanded ? channelPadding + choices.height : 0)

    function toggleDevices(trigger) {
        if (!devices.length) return;
        deviceTrigger = trigger;
        devicePickerRequested();
    }

    function chooseDevice(index) {
        if (index >= 0 && index < devices.length) deviceSelected(index);
    }

    function focusChoices() {
        if (!devicesExpanded || !devices.length || shell.pillHidden) return;
        choices.currentIndex = Math.max(0, selectedDevice);
        choices.positionViewAtIndex(choices.currentIndex, ListView.Contain);
        choices.forceActiveFocus();
    }

    onDevicesExpandedChanged: {
        if (devicesExpanded) Qt.callLater(focusChoices);
        else if (choices.activeFocus && visible && shell.panel === "mixer" && !shell.pillHidden)
            (deviceTrigger || selectorButton).forceActiveFocus();
    }

    onDevicesChanged: { if (devicesExpanded && !devices.length) devicePickerRequested(); }

    Rectangle {
        anchors.fill: parent
        radius: root.theme.overviewTileRadius
        color: root.theme.overviewControls
        PillOverviewSurface {
            anchors.fill: parent
            theme: root.theme
            radius: parent.radius
            frameOnly: true
            rimColor: "transparent"
            highlightColor: "#09fff3e8"
        }
    }

    TextMetrics { id: percentMetrics; font: root.theme.textFont; text: "100%" }

    RowLayout {
        id: controls
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: root.channelPadding }
        height: root.buttonSize
        spacing: root.theme.overviewControlGap

        IconButton {
            id: toggleButton
            objectName: "audioIcon:" + root.controlId
            readonly property color stateTint: root.muted ? root.theme.overviewSecondary : root.theme.overviewAccent
            enabled: root.available || root.devices.length > 0
            icon: root.icon
            hint: root.hint + (root.muted ? " · unmute" : " · mute") + "; right-click to choose device"
            iconTint: hovered || activeFocus ? Qt.lighter(stateTint, 1.15) : stateTint
            mouseButtons: Qt.LeftButton | Qt.RightButton
            onClicked: button => {
                if (button === Qt.RightButton) root.toggleDevices(toggleButton);
                else if (root.available) root.toggleRequested();
            }
            Keys.onMenuPressed: root.toggleDevices(toggleButton)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)) {
                    root.toggleDevices(toggleButton);
                    event.accepted = true;
                }
            }
        }
        PillSlider {
            id: fader
            objectName: "fader:" + root.controlId
            Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredHeight: root.buttonSize
            emberShell: root.shell; muted: root.muted
            backendValue: root.backendValue; enabled: root.available
            wheelEnabled: true
            onMoved: { root.focused(this); root.moved(value); }
            onHoveredChanged: { if (hovered) root.focused(this); }
            onActiveFocusChanged: { if (activeFocus) root.focused(this); }
            onPressedChanged: { if (pressed) root.focused(this); else root.released(value); }
            Accessible.name: root.hint
        }
        Text {
            Layout.preferredWidth: Math.ceil(percentMetrics.advanceWidth)
            horizontalAlignment: Text.AlignRight
            text: root.available ? Math.round(fader.value * 100) + "%" : "—"
            color: root.theme.overviewInk
            font: root.theme.textFont
        }
        IconButton {
            id: selectorButton
            objectName: root.selectorName + "Button"
            icon: root.devicesExpanded ? "chevron-up" : "chevron-down"
            iconTint: root.devicesExpanded || hovered || activeFocus ? root.theme.overviewAccent : root.theme.overviewInk
            hint: (root.devicesExpanded ? "Hide " : "Choose ") + root.controlId.toLowerCase() + " device"
            enabled: root.devices.length > 0
            onClicked: root.toggleDevices(selectorButton)
        }
    }

    ListView {
        id: choices
        objectName: root.selectorName
        anchors { top: controls.bottom; left: controls.left; right: controls.right; topMargin: root.channelPadding }
        readonly property int shownRows: Math.min(4, root.devices.length)
        height: shownRows * root.buttonSize + Math.max(0, shownRows - 1) * spacing
        spacing: root.theme.overviewControlGap
        visible: root.devicesExpanded
        clip: true
        model: visible ? root.devices : null
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        keyNavigationEnabled: true
        Accessible.name: root.controlId + " devices"
        PillWheel { flickable: choices }
        ScrollBar.vertical: ScrollBar {}
        Keys.onReturnPressed: root.chooseDevice(currentIndex)
        Keys.onEnterPressed: root.chooseDevice(currentIndex)
        Keys.onSpacePressed: root.chooseDevice(currentIndex)

        delegate: ItemDelegate {
            id: choice
            required property string modelData
            required property int index
            objectName: root.selectorName + ":" + index
            readonly property bool currentDevice: index === root.selectedDevice
            width: choices.width
            height: root.buttonSize
            leftPadding: root.theme.overviewGap; rightPadding: root.theme.overviewGap
            text: modelData
            hoverEnabled: true
            activeFocusOnTab: false
            Accessible.role: Accessible.RadioButton
            Accessible.checkable: true
            Accessible.checked: currentDevice
            background: Rectangle {
                radius: 12
                color: choice.currentDevice ? "#45a56c4c"
                    : choice.hovered || (choices.activeFocus && choice.ListView.isCurrentItem) ? root.theme.overviewButtonHover : "transparent"
            }
            contentItem: RowLayout {
                spacing: 8
                Text {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    text: choice.text
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font: root.theme.textFont
                    color: choice.currentDevice ? root.theme.weatherAccent : root.theme.overviewInk
                }
                ShellIcon {
                    visible: choice.currentDevice
                    name: "check"; tint: root.theme.overviewAccent
                    Layout.preferredWidth: 19; Layout.preferredHeight: 19
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            onClicked: root.chooseDevice(index)
        }
    }

    component IconButton: ShellButton {
        theme: root.theme
        Layout.preferredWidth: root.buttonSize; Layout.preferredHeight: root.buttonSize
        iconSize: root.theme.overviewControlIconSize
        color: "transparent"
        emberSlot.shapeOpacity: 0
    }
}
