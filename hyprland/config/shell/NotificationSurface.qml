import QtQuick

Item {
    id: root
    required property var theme
    property bool inset: false
    property bool critical: false
    property int depth: 0
    property real radius: 20
    Loader {
        anchors.fill: parent
        active: root.inset
        sourceComponent: PillOverviewSurface {
            theme: root.theme
            radius: root.radius
            glassStops: root.theme.notificationGlassStops[Math.min(root.depth, root.theme.notificationGlassStops.length - 1)]
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: !root.inset
        gradient: Gradient {
            GradientStop { position: 0; color: root.theme.glassTop }
            GradientStop { position: 1; color: root.theme.glassBottom }
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: !root.inset || root.critical
        radius: root.radius; color: "transparent"
        border.width: 1
        border.color: root.critical ? root.theme.red : Qt.alpha(root.theme.border, 0.16)
    }
}
