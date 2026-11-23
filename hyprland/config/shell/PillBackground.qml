// Adapted from Ricelin's PillBody.qml, copyright (c) 2026 Gakuseei.
// https://github.com/Gakuseei/Ricelin — MIT; see RICELIN-LICENSE.txt.
import QtQuick

Item {
    id: root
    required property var theme
    property real radius: 20
    property color tint: "transparent"
    Rectangle {
        id: fill
        anchors.fill: parent
        radius: root.radius
        color: root.tint
        gradient: root.tint.a > 0 ? null : glass
        Gradient {
            id: glass
            GradientStop { position: 0; color: root.theme.glassTop }
            GradientStop { position: 1; color: root.theme.glassBottom }
        }
    }
}
