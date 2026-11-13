import QtQuick
import Quickshell

// Retain a banner's geometry and pixels until it is completely off-screen.
Item {
    id: root
    required property var theme
    required property var store
    required property var entry
    property bool presented: true
    property real travel: width + theme.panelGap
    property real offset: travel
    property real heldHeight: 0
    property bool ready: false
    property bool retiredSent: false
    readonly property alias inputRegion: input
    signal retired()
    x: offset
    implicitHeight: !presented && heldHeight > 0 ? heldHeight : card.implicitHeight
    enabled: presented && ready

    function animate() {
        if (!ready) return;
        motion.stop();
        motion.to = presented ? 0 : travel;
        motion.restart();
    }
    onPresentedChanged: {
        heldHeight = presented ? 0 : Math.max(1, card.height);
        if (presented) retiredSent = false;
        animate();
    }
    onTravelChanged: { if (!ready) offset = travel; else if (!presented) animate(); }
    NumberAnimation {
        id: motion
        target: root; property: "offset"
        duration: 220; easing.type: Easing.OutCubic
        onFinished: {
            if (!root.presented && !root.retiredSent) {
                root.retiredSent = true;
                root.retired();
            }
        }
    }
    Connections {
        target: root.Window.window
        enabled: !root.ready
        function onFrameSwapped() { root.ready = true; root.animate(); }
    }
    // Follow the visible card all the way out; retire the region with its item.
    Region { id: input; item: root }
    NotificationCard {
        id: card
        objectName: "notification-banner-card"
        width: root.width; height: root.height
        theme: root.theme; store: root.store; entry: root.entry
    }
}
