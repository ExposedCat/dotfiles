import QtQuick

Item {
    id: root
    required property var theme
    required property real sourceWidth
    property real sourceRight: sourceWidth
    // The old visible gap included the drop's concave shoulder plus 10px.
    readonly property real gap: (sourceWidth - sourceRight + 10) / 2
    property bool present: false
    property real separation: present ? 1 : 0
    readonly property alias bubbleItem: bubble
    signal clicked()
    width: sourceWidth + 40
    z: -1 // Slide out from behind the clock, and back underneath it.
    Behavior on separation { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Rectangle {
        id: bubble
        width: 20; height: 20; radius: 10
        x: root.sourceRight - width + (width + root.gap) * root.separation
        y: (root.theme.panelHeight - height) / 2
        color: "white"
        visible: root.separation > 0.001
        Accessible.role: Accessible.Button
        Accessible.name: "Active notifications"
        Accessible.onPressAction: root.clicked()
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }
    }
}
