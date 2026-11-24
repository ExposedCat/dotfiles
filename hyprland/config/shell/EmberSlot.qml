import QtQuick

// A destination for the single shared shape, below this control's own content.
Item {
    id: root
    required property var shell
    property Item ember: null
    property EmberHoverGroup hoverGroup: null
    property real shapeRadius: Math.min(width, height) / 2
    property real shapeBend: 0
    property real shapeOpacity: 1
    property real shapeBorderWidth: 0
    readonly property Item motion: ember || shell?.pill?.ember || null
    readonly property bool landed: occupied && motion?.dock === root && !motion.moving
    property bool caret: false
    property var motionKey: null
    property point motionOffset: Qt.point(0, 0)
    readonly property bool occupied: ember ? ember.active && ember.target === root
        : !!shell && shell.emberEnabled && shell.emberTarget === root
}
