import QtQuick

// Own the interruptible popup motion independently of the native window.
Item {
    id: motion
    required property var shell
    required property var theme
    visible: shown.length > 0
    property string shown: ""
    property string confirmAction: ""
    property bool expanded: false
    property bool pendingOpen: false
    readonly property int animationDuration: 140
    property real requestedOriginX: 0
    property real requestedOriginWidth: 56
    property real originX: requestedOriginX
    property real originWidth: requestedOriginWidth
    property real progress: expanded ? 1 : 0
    property real screenWidth: 1920
    property real screenHeight: 1080
    readonly property real shoulder: theme.panelWing + Math.min(12, Math.max(0, requestedOriginWidth - theme.panelWing * 2) / 8)
    readonly property bool leftEdge: requestedOriginX <= 7
    readonly property bool rightEdge: requestedOriginX + requestedOriginWidth >= screenWidth - 7
    readonly property real requestedWidth: Math.min(shown === "notifications" ? 1040 : shown === "power" ? 316 : shown === "ethernet" ? 390 : 400, screenWidth - 12 - (leftEdge || rightEdge ? shoulder : 0))
    readonly property real requestedHeight: shown === "notifications" ? Math.min(820, screenHeight - 64) : shown === "power" ? 180 : shown === "bluetooth" ? Math.min(500, screenHeight - 64) : 232
    readonly property real requestedX: leftEdge ? requestedOriginX + shoulder : rightEdge ? requestedOriginX + requestedOriginWidth - shoulder - requestedWidth : Math.max(6, Math.min(screenWidth - requestedWidth - 6, requestedOriginX + requestedOriginWidth / 2 - requestedWidth / 2))
    property real targetWidth: requestedWidth
    property real targetHeight: requestedHeight
    property real targetX: requestedX
    readonly property bool moving: originMove.running || originResize.running || popupMove.running || popupResizeWidth.running || popupResizeHeight.running
    function begin() {
        if (!shell.panel) return;
        pendingOpen = true;
        expanded = false;
        selectPanel();
    }
    function selectPanel() {
        shown = shell.panel;
        requestedOriginX = shell.panelOriginX;
        requestedOriginWidth = shell.panelOriginWidth;
        confirmAction = "";
    }
    function sync() {
        if (!shell.panel) {
            pendingOpen = false;
            expanded = false;
            if (progress === 0) shown = "";
            return;
        }
        if (shown === shell.panel) { if (!pendingOpen) expanded = !!shown; return; }
        if (shown && progress > 0) {
            // Retarget the current popup immediately, even during a close or
            // another switch. Preserve expansion while its outline morphs.
            pendingOpen = false;
            selectPanel();
            expanded = true;
        } else begin();
    }
    // The window calls this after presenting the closed attachment once.
    function frameReady() {
        if (pendingOpen && shown === shell.panel) {
            pendingOpen = false;
            expanded = true;
        }
    }
    onProgressChanged: {
        if (progress === 0 && !expanded && !shell.panel) shown = "";
    }
    Behavior on progress { NumberAnimation { duration: motion.animationDuration; easing.type: Easing.InOutCubic } }
    Behavior on originX { enabled: motion.progress > 0 && !motion.pendingOpen; NumberAnimation { id: originMove; duration: motion.animationDuration; easing.type: Easing.InOutCubic } }
    Behavior on originWidth { enabled: motion.progress > 0 && !motion.pendingOpen; NumberAnimation { id: originResize; duration: motion.animationDuration; easing.type: Easing.InOutCubic } }
    Behavior on targetX { enabled: motion.progress > 0 && !motion.pendingOpen; NumberAnimation { id: popupMove; duration: motion.animationDuration; easing.type: Easing.InOutCubic } }
    Behavior on targetWidth { enabled: motion.progress > 0 && !motion.pendingOpen; NumberAnimation { id: popupResizeWidth; duration: motion.animationDuration; easing.type: Easing.InOutCubic } }
    Behavior on targetHeight { enabled: motion.progress > 0 && !motion.pendingOpen; NumberAnimation { id: popupResizeHeight; duration: motion.animationDuration; easing.type: Easing.InOutCubic } }
    Connections { target: motion.shell; function onPanelChanged() { Qt.callLater(motion.sync); } }
}
