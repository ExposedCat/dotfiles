// Adapted from Ricelin's PillBody.qml, copyright (c) 2026 Gakuseei.
// https://github.com/Gakuseei/Ricelin — MIT; see RICELIN-LICENSE.txt.
import QtQuick

Item {
    id: root
    required property var theme
    property real radius: 20
    Rectangle {
        id: fill
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0; color: root.theme.glassTop }
            GradientStop { position: 1; color: root.theme.glassBottom }
        }
    }
}
