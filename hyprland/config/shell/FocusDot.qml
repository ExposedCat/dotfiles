import QtQuick

Rectangle {
    required property var theme
    anchors { top: parent.top; right: parent.right; margins: 4 }
    width: 6
    height: width
    radius: width / 2
    color: theme.focusColor
}
