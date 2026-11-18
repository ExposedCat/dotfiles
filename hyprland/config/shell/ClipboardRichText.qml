import QtQuick

Item {
    id: root
    required property var theme
    required property string html
    readonly property int padding: 10
    implicitHeight: Math.ceil(preview.contentHeight) + 2 * padding
    Item {
        anchors { fill: parent; margins: root.padding }
        clip: true
        Text {
            id: preview
            anchors { top: parent.top; left: parent.left; right: parent.right }
            text: root.html
            textFormat: Text.RichText
            wrapMode: Text.WrapAnywhere
            font: root.theme.textFont
            color: root.theme.text
        }
    }
}
