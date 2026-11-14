import QtQuick
import QtQuick.Controls

Slider {
    id: root
    required property var theme
    property real backendValue: 0
    Binding { target: root; property: "value"; value: root.backendValue; when: !root.pressed; restoreMode: Binding.RestoreNone }
    property var emberShell: null
    property alias emberSlot: handleSlot
    from: 0; to: 1
    implicitWidth: horizontal ? 200 : 32
    implicitHeight: horizontal ? 30 : 132
    background: Rectangle {
        x: root.leftPadding + (root.horizontal ? 0 : Math.round((root.availableWidth - width) / 2))
        y: root.topPadding + (root.horizontal ? Math.round((root.availableHeight - height) / 2) : 0)
        width: root.horizontal ? root.availableWidth : 2
        height: root.horizontal ? 4 : root.availableHeight
        radius: width / 2
        color: root.horizontal ? root.theme.surface : Qt.alpha(root.theme.text, 0.18)
        Rectangle {
            x: 0; y: root.horizontal ? 0 : parent.height - height
            width: root.horizontal ? parent.width * root.position : parent.width
            height: root.horizontal ? parent.height : parent.height * root.position
            radius: 2
            color: !root.horizontal && root.emberSlot && root.emberSlot.occupied ? "#cc7855" : root.theme.accent
            opacity: root.horizontal ? 1 : 0.72
        }
    }
    handle: Rectangle {
        x: root.leftPadding + (root.horizontal ? root.visualPosition * (root.availableWidth - width) : Math.round((root.availableWidth - width) / 2))
        y: root.topPadding + (root.horizontal ? Math.round((root.availableHeight - height) / 2) : root.visualPosition * (root.availableHeight - height))
        width: root.horizontal ? (root.pressed ? 15 : 12) : 14
        height: root.horizontal ? width : 4
        radius: Math.min(width, height) / 2
        EmberSlot { id: handleSlot; shell: root.emberShell; anchors.fill: parent }
        color: handleSlot.occupied ? "transparent" : root.theme.text
        border.width: root.activeFocus && !handleSlot.occupied && root.horizontal ? 2 : 0; border.color: root.theme.accent
    }
}
