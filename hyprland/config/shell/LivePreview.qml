import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
    id: root
    property var sourceData: ({})
    property var theme
    property bool fixture: false
    readonly property bool hasContent: capture.hasContent
    readonly property var target: {
        if (sourceData.kind === "screen") return Quickshell.screens.find(s => s.name === sourceData.output) || null;
        if (sourceData.kind === "window") {
            const matches = ToplevelManager.toplevels.values.filter(t => t.appId === sourceData.appId && t.title === sourceData.name);
            return matches.length === 1 ? matches[0] : null;
        }
        return null;
    }
    ScreencopyView {
        id: capture
        anchors.fill: parent
        captureSource: root.target
        live: root.visible && !!root.target
        paintCursor: false
        constraintSize: Qt.size(640, 360)
    }
}
