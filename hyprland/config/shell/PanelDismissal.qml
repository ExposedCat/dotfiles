import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property var popup
    required property rect popupRect
    property rect attachmentRect: Qt.rect(0, 0, 0, 0)
    property int panelHeight: 30
    property bool enabled: true
    signal dismissed()

    // Dismiss only on an actual outside press. Focus changes (including ending
    // an inline reply) and wheel events are not outside clicks.
    PanelWindow {
        id: outside
        screen: root.popup.screen
        visible: root.enabled && root.popup.visible
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "dotfiles-panel-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {
            width: outside.width; height: outside.height
            Region { x: root.popupRect.x; y: root.popupRect.y; width: root.popupRect.width; height: root.popupRect.height; intersection: Intersection.Subtract }
            Region { x: root.attachmentRect.x; y: root.attachmentRect.y; width: root.attachmentRect.width; height: root.attachmentRect.height; intersection: Intersection.Subtract }
            Region { width: outside.width; height: root.panelHeight; intersection: Intersection.Subtract }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onPressed: root.dismissed()
            onWheel: event => event.accepted = false
        }
    }
}
