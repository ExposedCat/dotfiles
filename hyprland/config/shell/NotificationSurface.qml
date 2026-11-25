import QtQuick

Item {
    id: root
    required property var theme
    property bool critical: false
    property int depth: 0
    property real radius: 20
    PillOverviewSurface {
        anchors.fill: parent
        theme: root.theme
        radius: root.radius
        glassStops: root.theme.notificationGlassStops[Math.min(root.depth, root.theme.notificationGlassStops.length - 1)]
    }
    Rectangle {
        anchors.fill: parent
        visible: root.critical
        radius: root.radius; color: "transparent"
        border.width: 1
        border.color: root.theme.red
    }
}
