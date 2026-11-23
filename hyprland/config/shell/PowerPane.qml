import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    property Item shutdownButton: null
    readonly property Item emberTarget: shutdownButton ? arrival : null
    property string confirmAction: ""
    spacing: 8

    Connections {
        target: root.shell
        function onPanelChanged() { if (root.shell.panel !== "power") root.confirmAction = ""; }
    }

    // The opening hop ends beside the glow. Hover and keyboard focus use the
    // buttons' own slots so that the dot can expand into the button background.
    EmberSlot {
        id: arrival
        parent: root.shutdownButton
        anchors.centerIn: parent
        shell: root.shell
        width: 1; height: 1
        shapeOpacity: 0
    }

    RowLayout {
        id: actions
        readonly property EmberHoverGroup emberHoverGroup: EmberHoverGroup { parent: actions }
        readonly property real buttonSize: Math.min(root.theme.overviewControlSize,
            Math.max(0, (root.width - (buttons.count - 1) * root.theme.overviewControlGap) / Math.max(1, buttons.count)))
        Layout.alignment: Qt.AlignHCenter
        spacing: Math.max(root.theme.overviewControlGap,
            (root.width - buttons.count * buttonSize) / (buttons.count + 1))

        Repeater {
            id: buttons
            model: [
                {id: "lock", title: "Lock", icon: "lock-keyhole"},
                {id: "suspend", title: "Suspend", icon: "moon"},
                {id: "logout", title: "Log out", icon: "log-out", danger: true},
                {id: "reboot", title: "Restart", icon: "rotate-cw", danger: true},
                {id: "poweroff", title: "Shut down", icon: "power", danger: true}
            ]
            PillControl {
                required property var modelData
                Component.onCompleted: { if (modelData.id === "poweroff") root.shutdownButton = this; }
                implicitWidth: actions.buttonSize
                theme: root.theme; icon: modelData.icon; preferredIconSize: 32
                hint: (selected ? "Confirm " : "") + modelData.title
                selected: root.confirmAction === modelData.id
                danger: !!modelData.danger
                onClicked: {
                    if (danger && !selected) root.confirmAction = modelData.id;
                    else { root.shell.power(modelData.id); root.shell.panel = ""; }
                }
            }
        }
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        visible: root.confirmAction.length > 0
        text: "Click again to confirm"
        color: root.theme.secondary; font: root.theme.textFont
    }
    Text { Layout.fillWidth: true; text: root.shell.actionError; visible: text.length > 0; color: root.theme.red; wrapMode: Text.Wrap; font: root.theme.textFont }
}
