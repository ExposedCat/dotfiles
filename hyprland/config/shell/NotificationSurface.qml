import QtQuick

// Lift the center's glass above the pill background so each card stays distinct.
Item {
    id: root
    required property var theme
    property bool inset: false
    property bool critical: false
    property real radius: 20
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0; color: root.inset ? Qt.alpha(root.theme.hover, 0.52) : root.theme.glassTop }
            GradientStop { position: 1; color: root.inset ? Qt.alpha(root.theme.surface, 0.72) : root.theme.glassBottom }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius; color: "transparent"
        border.width: 1
        border.color: root.critical ? root.theme.red : Qt.alpha(root.theme.border, root.inset ? 0.28 : 0.16)
    }
}
