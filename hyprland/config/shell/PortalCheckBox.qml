import QtQuick
import QtQuick.Controls

CheckBox {
    font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize
    id: root
    required property var theme
    property bool focusDotVisible: activeFocus
    implicitHeight: 32
    spacing: 9
    padding: 0
    indicator: Rectangle {
        implicitWidth: 18; implicitHeight: 18
        x: 0; y: (root.height - height) / 2
        radius: 5
        color: root.checked ? root.theme.focusColor : root.theme.surface
        border.width: 1; border.color: root.checked ? root.theme.focusColor : root.theme.border
        Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; anchors.centerIn: parent; visible: root.checked; text: "✓"; color: "#101010" }
        FocusDot {
            theme: root.theme
            visible: root.focusDotVisible
            anchors.topMargin: -3; anchors.rightMargin: -3
        }
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
