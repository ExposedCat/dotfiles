import QtQuick

// Content inside the pill's one expanding body; no separate background/window.
Item {
    id: root
    required property var shell
    required property var theme
    required property var spaces
    property bool workspace: false
    property bool showing: false
    property real reveal: showing ? 1 : 0
    readonly property real naturalWidth: workspace ? switches.implicitWidth : 84
    property alias workspaceIndicator: switches
    width: naturalWidth; height: 40
    opacity: reveal
    visible: !shell.pillHidden && reveal > 0
    Behavior on reveal { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    WorkspaceDots {
        id: switches
        shell: root.shell; theme: root.theme; spaces: root.spaces; floating: true; implicitHeight: 40
        fixtureActive: Math.max(0, root.spaces.findIndex(s => String(s.id) === root.shell.osd.workspaceLabel))
        visible: root.workspace
    }
    Rectangle {
        visible: !root.workspace
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 12; radius: 6
        color: "#685f59"
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.shell.osd.level)); height: parent.height; radius: 6
            color: root.shell.osd.muted ? root.theme.secondary : root.theme.text
            Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.shell.toggle("mixer") }
    }
}
