import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var shell
    required property var theme
    property string kind: "osd"
    property var entry: null
    property var heldEntry: ({id: "", summary: "", body: "", app: "", icon: ""})
    readonly property real contentHeight: kind === "notification" && card.item ? card.item.implicitHeight + 16 : 88
    implicitHeight: contentHeight
    onEntryChanged: { if (entry) heldEntry = entry; }
    signal expandRequested()
    MouseArea {
        anchors.fill: parent; enabled: root.kind === "osd"; cursorShape: Qt.PointingHandCursor
        onClicked: { if (root.shell.osd.kind === "workspace") root.expandRequested(); else root.shell.toggle("mixer"); }
    }
    ColumnLayout {
        anchors { fill: parent; margins: 18 }
        visible: root.kind === "osd"; spacing: 10
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            ShellIcon { name: root.shell.osd.icon; Layout.preferredWidth: 21; Layout.preferredHeight: 21 }
            Text { Layout.fillWidth: true; text: root.shell.osd.title; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; elide: Text.ElideRight }
            Text { text: root.shell.osd.valueText; color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize }
        }
        Rectangle {
            visible: root.shell.osd.kind !== "workspace"
            Layout.fillWidth: true; implicitHeight: 4; radius: 2; color: root.theme.surface
            Rectangle { width: parent.width * Math.max(0, Math.min(1, root.shell.osd.level)); height: parent.height; radius: 2; color: root.shell.osd.muted ? root.theme.secondary : root.theme.accent }
        }
    }
    Loader {
        id: card
        x: 12; y: 8; width: parent.width - 24
        active: root.kind === "notification"
        visible: active
        sourceComponent: NotificationCard { theme: root.theme; store: root.shell.notifications; entry: root.heldEntry; embedded: true; height: implicitHeight }
    }
}
