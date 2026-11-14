import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    property Item hoveredButton: null
    property Item focusedButton: null
    readonly property Item emberTarget: (hoveredButton || focusedButton)?.emberSlot || null
    property string confirmAction: ""
    spacing: 12
    Repeater {
        model: [
            [{id: "lock", title: "Lock", icon: "lock-keyhole"}, {id: "suspend", title: "Suspend", icon: "moon"}],
            [{id: "logout", title: "Log out", icon: "log-out"}, {id: "reboot", title: "Restart", icon: "rotate-cw"}, {id: "poweroff", title: "Shut down", icon: "power"}]
        ]
        RowLayout {
            required property var modelData
            Layout.alignment: Qt.AlignHCenter; spacing: 12
            Repeater {
                model: modelData
                ShellButton {
                    required property var modelData
                    emberShell: root.shell
                    onHoveredChanged: { if (hovered) root.hoveredButton = this; else if (root.hoveredButton === this) root.hoveredButton = null; }
                    onActiveFocusChanged: { if (activeFocus) root.focusedButton = this; else if (root.focusedButton === this) root.focusedButton = null; }
                    implicitWidth: 70; implicitHeight: 60; radius: 20
                    theme: root.theme; icon: modelData.icon; iconSize: 26
                    hint: (root.confirmAction === modelData.id ? "Confirm " : "") + modelData.title
                    selected: root.confirmAction === modelData.id
                    color: emberSlot.occupied ? "transparent" : selected ? root.theme.hover : root.theme.surface
                    danger: ["logout", "reboot", "poweroff"].includes(modelData.id)
                    onClicked: {
                        if (danger && root.confirmAction !== modelData.id) root.confirmAction = modelData.id;
                        else { root.shell.power(modelData.id); root.shell.panel = ""; }
                    }
                }
            }
        }
    }
    Text { Layout.alignment: Qt.AlignHCenter; text: root.confirmAction ? "Click again to confirm" : ""; color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize }
    Text { Layout.fillWidth: true; text: root.shell.actionError; visible: text.length > 0; color: root.theme.red; wrapMode: Text.Wrap; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize }
}
