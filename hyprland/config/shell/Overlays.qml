import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    required property var shell
    required property var theme
    property bool showOsd: true
    property alias bannerWindow: toasts
    property alias banners: toastBanners
    PanelWindow {
        id: toasts
        screen: root.shell.mainScreen
        visible: toastBanners.presentationCount > 0
        anchors { top: true; right: true }
        margins { top: root.theme.panelHeight + root.theme.panelGap; right: 0 }
        implicitWidth: root.theme.notificationWidth + root.theme.panelGap
        // Card hover changes only the input region and card height. Keeping the
        // Wayland window fixed prevents configure/leave/re-enter oscillation.
        implicitHeight: Math.max(1, (screen ? screen.height : 1080) - margins.top)
        mask: Region { regions: toastBanners.inputRegions }
        exclusionMode: ExclusionMode.Ignore; color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dotfiles-notifications"
        WlrLayershell.keyboardFocus: bannerFocus.keyboardMode
        ReplyFocus { id: bannerFocus; store: root.shell.notifications; surface: "banner"; targetWindow: toasts }
        NotificationBanners {
            id: toastBanners
            width: parent.width
            theme: root.theme; store: root.shell.notifications
            active: root.shell.panel !== "notifications"
        }
    }
    PanelWindow {
        screen: Quickshell.screens.find(s => s.name === root.shell.osd.output) || root.shell.focusedScreen
        visible: root.showOsd && root.shell.osd.visible
        anchors { bottom: true }
        margins.bottom: 90
        implicitWidth: 350; implicitHeight: 88; exclusiveZone: -1; color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dotfiles-osd"
        OsdCard {
            anchors.fill: parent
            osd: root.shell.osd; theme: root.theme
        }
    }
}
