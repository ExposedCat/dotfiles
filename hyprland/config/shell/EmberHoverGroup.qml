import QtQuick

HoverHandler {
    property real holdHeight: parent?.height ?? 0
    readonly property bool holding: hovered && point.position.y < holdHeight
}
