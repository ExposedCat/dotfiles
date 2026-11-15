import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property var osd
    required property var theme
    implicitWidth: 350; implicitHeight: 88
    radius: 16; color: theme.background; border.width: 1; border.color: theme.border
    ColumnLayout {
        anchors { fill: parent; margins: 17 }
        spacing: 12
        RowLayout {
            ShellIcon { name: root.osd.icon; Layout.preferredWidth: 21; Layout.preferredHeight: 21 }
            Text { font: root.theme.textFont; Layout.fillWidth: true; elide: Text.ElideRight; text: root.osd.title; color: root.theme.text }
            Text { font: root.theme.textFont; text: root.osd.valueText; color: root.theme.text }
        }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 5; radius: 3; color: root.theme.surface
            Rectangle { height: parent.height; width: parent.width * Math.max(0, Math.min(1, root.osd.level)); radius: 3; color: root.osd.muted ? root.theme.secondary : root.theme.accent }
        }
    }
}
