import QtQuick

ShellButton {
    id: root
    property int horizontalPadding: 16
    readonly property real bodyRightEdge: width - dropSurface.shoulder
    implicitWidth: Math.max(56, implicitContentWidth + horizontalPadding * 2) + theme.panelWing * 2
    implicitHeight: theme.panelHeight
    iconSize: 18
    radius: 0
    color: "transparent"
    border.width: 0
    NotchSurface {
        id: dropSurface
        anchors.fill: parent
        z: -1
        wing: root.theme.panelWing
        color: root.theme.background
    }
}
