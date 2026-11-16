import QtQuick
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: root
    required property var theme
    required property var modelData
    required property int index
    property bool selected: false
    property bool favorite: false
    signal pointerMoved(real x, real y)
    signal activated()
    height: 52; radius: 10
    color: selected ? Qt.alpha(theme.hover, 0.58) : "transparent"
    border.width: selected ? 1 : 0; border.color: Qt.alpha(theme.border, 0.22)
    RowLayout {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
        spacing: 8
        Item {
            Layout.preferredWidth: 34; Layout.preferredHeight: 36
            Image {
                id: resultIcon; anchors.centerIn: parent; width: 32; height: 32
                source: root.modelData.icon ? (root.modelData.icon.startsWith("/") ? "file://" + root.modelData.icon : Quickshell.iconPath(root.modelData.icon, true)) : ""
                visible: status === Image.Ready
                sourceSize.width: 64; sourceSize.height: 64; fillMode: Image.PreserveAspectFit
            }
            Text {
                anchors.centerIn: parent; visible: !resultIcon.visible
                text: root.modelData.glyph || ({app: "◇", file: "▤", bookmark: "↗", web: "⌕", currency: "⇄", date: "◷", calculation: "="})[root.modelData.kind] || "·"
                width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                font: root.theme.textFont; color: root.theme.text; textFormat: Text.PlainText
            }
        }
        Text { Layout.fillWidth: true; text: root.modelData.name; textFormat: Text.PlainText; font: root.theme.textFont; color: root.theme.text; elide: Text.ElideRight }
        Text {
            Layout.preferredWidth: Math.min(implicitWidth, root.width * 0.44)
            text: root.modelData.kind === "currency" ? (root.modelData.rateDate || "") : root.modelData.description || ""
            textFormat: Text.PlainText; horizontalAlignment: Text.AlignRight
            font: root.theme.textFont
            color: root.theme.secondary; elide: Text.ElideRight
        }
        Text { text: "★"; visible: root.favorite; color: "#cc7855"; font: root.theme.textFont }
    }
    MouseArea {
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onPositionChanged: mouse => root.pointerMoved(mouse.x, mouse.y)
        onClicked: root.activated()
    }
    Accessible.role: Accessible.Button
    Accessible.name: modelData.name + ". " + (modelData.description || "")
    Accessible.onPressAction: activated()
}
