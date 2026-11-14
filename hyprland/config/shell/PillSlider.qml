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
    implicitHeight: 30
    background: Rectangle {
        x: root.leftPadding; y: Math.round((root.height - height) / 2)
        width: root.availableWidth; height: 4; radius: 2; color: root.theme.surface
        Rectangle { width: parent.width * root.visualPosition; height: parent.height; radius: 2; color: root.theme.accent }
    }
    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: Math.round((root.height - height) / 2)
        width: root.pressed ? 15 : 12; height: width; radius: width / 2
        EmberSlot { id: handleSlot; shell: root.emberShell; anchors.fill: parent }
        color: handleSlot.occupied ? "transparent" : root.theme.text
        border.width: root.activeFocus && !handleSlot.occupied ? 2 : 0; border.color: root.theme.accent
    }
}
