import QtQuick
import QtQuick.Controls

CheckBox {
    font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize
    id: root
    required property var theme
    implicitHeight: 32
    spacing: 9
    padding: 0
    indicator: Rectangle {
        implicitWidth: 18; implicitHeight: 18
        x: 0; y: (root.height - height) / 2
        radius: 5
        color: root.checked ? root.theme.accent : root.theme.surface
        border.width: 1; border.color: root.activeFocus ? root.theme.text : root.checked ? root.theme.accent : "#666666"
        Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; anchors.centerIn: parent; visible: root.checked; text: "✓"; color: "#101010" }
    }
    contentItem: Text {
        font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize
        text: root.text; textFormat: Text.PlainText
        leftPadding: root.indicator.width + root.spacing
        verticalAlignment: Text.AlignVCenter
        color: root.theme.secondary;
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
