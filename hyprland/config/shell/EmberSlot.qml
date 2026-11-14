import QtQuick

// A destination for the single shared shape, below this control's own content.
Item {
    id: root
    required property var shell
    property real shapeRadius: Math.min(width, height) / 2
    property real shapeOpacity: 1
    readonly property bool landed: occupied && shell.pill.ember.dock === root && !shell.pill.ember.moving
    property bool caret: false
    property var motionKey: null
    readonly property bool occupied: !!shell && shell.emberEnabled && shell.emberTarget === root
}
