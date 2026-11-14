import QtQuick
import QtQuick.Controls

ComboBox {
    id: root
    required property var theme
    implicitHeight: 42
    font.family: theme.fontFamily; font.pixelSize: theme.bodySize
    leftPadding: 14; rightPadding: 36
    background: Rectangle { color: root.theme.surface; radius: 12 }
    contentItem: Text {
        text: root.displayText; textFormat: Text.PlainText; color: root.theme.text
        font: root.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
    }
    indicator: ShellIcon { name: "chevron-down"; x: root.width - width - 12; y: Math.round((root.height - height) / 2); opacity: root.enabled ? 1 : 0.4 }
    delegate: ItemDelegate {
        required property var modelData
        required property int index
        width: root.width - 16; height: 40
        highlighted: root.highlightedIndex === index
        background: Rectangle { color: parent.highlighted ? root.theme.hover : "transparent"; radius: 8 }
        contentItem: Text { text: String(modelData); textFormat: Text.PlainText; color: root.theme.text; font: root.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
    }
    popup: Popup {
        y: root.height + 6; width: root.width; padding: 8
        implicitHeight: Math.min(260, choices.contentHeight + 16)
        background: Rectangle { color: root.theme.background; radius: 12 }
        contentItem: ListView {
            id: choices
            clip: true; implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
        }
    }
}
