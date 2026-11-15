import QtQuick

Rectangle {
    id: root
    required property var theme
    property int count: 1
    implicitWidth: Math.max(28, label.implicitWidth + 14)
    implicitHeight: 28
    radius: height / 2
    gradient: Gradient {
        GradientStop { position: 0; color: Qt.alpha(root.theme.hover, 0.32) }
        GradientStop { position: 1; color: Qt.alpha(root.theme.surface, 0.22) }
    }
    border.width: 1; border.color: Qt.alpha(theme.border, 0.12)
    Text {
        id: label
        anchors.centerIn: parent
        text: root.count; color: root.theme.secondary
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize
    }
}
