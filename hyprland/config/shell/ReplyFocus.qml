import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root
    required property var store
    required property string surface
    required property var targetWindow
    property var grab: null
    property bool available: true
    readonly property bool editing: available && (surface === "banner" ? store.bannerReplyActive : store.centerReplyActive)
    readonly property int keyboardMode: editing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    // Ordinary banners/popovers never request focus. Only an explicit Reply
    // click activates this Hyprland focus request. Clicking another app clears
    // the request without dismissing the popup or destroying the draft.
    Component { id: focusGrab; HyprlandFocusGrab {} }
    Component.onCompleted: {
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
            grab = focusGrab.createObject(root, {windows: [targetWindow]});
    }
    onEditingChanged: { if (!editing && grab) grab.active = false; }
    Connections {
        target: root.store
        function onReplyFocusRequested(surface) {
            if (surface === root.surface && root.grab)
                Qt.callLater(() => { if (root.editing) root.grab.active = true; });
        }
    }
}
