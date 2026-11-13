import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property var theme
    property string text: ""
    property bool primary: false
    signal clicked()
    implicitWidth: Math.max(76, label.implicitWidth + 28)
    implicitHeight: 36
    radius: 8
    color: !enabled ? theme.surface : primary ? theme.accent : pointer.containsMouse ? theme.hover : theme.surface
    border.width: activeFocus ? 2 : 0
    border.color: theme.text
    opacity: enabled ? 1 : 0.45
    scale: pointer.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: clicked()
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; id: label; anchors.centerIn: parent; text: root.text; textFormat: Text.PlainText; color: root.primary && root.enabled ? "#101010" : root.theme.text }
    MouseArea { id: pointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
}
