import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property var screen
    property bool topRounded: false
    property bool bottomRounded: false
    property int radius: 16

    // Thin, input-transparent strips also cover fullscreen windows without
    // reserving desktop space or allocating a full-screen overlay buffer.
    Variants {
        model: [true, false]
        PanelWindow {
            required property bool modelData
            screen: root.screen
            visible: modelData ? root.topRounded : root.bottomRounded
            anchors { top: modelData; bottom: !modelData; left: true; right: true }
            implicitHeight: root.radius
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "dotfiles-screen-corners"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            CornerMask {
                anchors.left: parent.left
                width: root.radius; height: root.radius
                rotation: modelData ? 0 : 270
            }
            CornerMask {
                anchors.right: parent.right
                width: root.radius; height: root.radius
                rotation: modelData ? 90 : 180
            }
        }
    }
}
