import QtQuick

Item {
    id: root
    property bool running: true
    implicitWidth: 22
    implicitHeight: 22
    ShellIcon { anchors.fill: parent; name: "loader-circle" }
    RotationAnimator on rotation { from: 0; to: 360; duration: 850; loops: Animation.Infinite; running: root.running && root.visible }
}
