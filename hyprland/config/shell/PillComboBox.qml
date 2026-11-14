import QtQuick
import QtQuick.Controls

ComboBox {
    id: root
    required property var theme
    property real menuWidth: width
    property string emptyText: ""
    implicitHeight: flat ? 30 : 42
    font.family: theme.fontFamily; font.pixelSize: theme.bodySize
    leftPadding: flat ? 0 : 14; rightPadding: flat ? 26 : 36
    background: Rectangle { color: root.flat ? "transparent" : Qt.alpha(root.theme.text, 0.06); radius: 10 }
    contentItem: Text {
        text: root.count ? root.displayText : root.emptyText; textFormat: Text.PlainText; color: root.flat ? root.theme.secondary : root.theme.text
        font: root.font; verticalAlignment: Text.AlignVCenter; horizontalAlignment: root.flat ? Text.AlignHCenter : Text.AlignLeft; elide: Text.ElideRight
    }
    indicator: ShellIcon { name: "chevron-down"; width: 21; height: 21; x: root.width - width - (root.flat ? 1 : 12); y: Math.round((root.height - height) / 2); opacity: root.enabled ? 1 : 0.4 }
    HoverHandler { enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
    delegate: ItemDelegate {
        required property var modelData
        required property int index
        width: root.popup.width - 16; height: 40
        highlighted: root.highlightedIndex === index
        background: Rectangle { color: parent.highlighted ? root.theme.hover : "transparent"; radius: 8 }
        contentItem: Text { text: String(modelData); textFormat: Text.PlainText; color: root.theme.text; font: root.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
    }
    popup: Popup {
        x: root.flat ? Math.round((root.width - width) / 2) : 0
        y: root.height + 6; width: Math.max(root.width, root.menuWidth); padding: 8
        implicitHeight: Math.min(260, choices.contentHeight + 16)
        background: Rectangle { color: root.theme.background; radius: 12 }
        contentItem: ListView {
            id: choices
            clip: true; implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            PillWheel { flickable: choices }
            ScrollBar.vertical: ScrollBar {}
        }
    }
}
