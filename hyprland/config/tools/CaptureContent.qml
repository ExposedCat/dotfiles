import QtQuick

// UI chrome is a sibling, so it can never enter the saved image.
Item {
    id: root
    required property var controller
    readonly property var selection: controller.selection
    readonly property var strokes: controller.draft ? controller.strokes.concat([controller.draft]) : controller.strokes
    width: Math.max(1, selection.width); height: Math.max(1, selection.height)
    clip: true
    function repaint() { content.repaint(); }
    CaptureLayer {
        id: content
        anchors.fill: parent
        controller: root.controller
        strokes: root.strokes
        limit: root.strokes.length
    }
}
