import QtQuick
import Quickshell.Hyprland

Item {
    id: root
    required property var shell
    required property var theme
    required property var spaces
    property int fixtureActive: 0
    readonly property int current: shell.fixture ? Math.min(fixtureActive, Math.max(0, spaces.length - 1)) : Math.max(0, spaces.findIndex(w => w.active))
    readonly property real gap: 10
    readonly property real dot: 7
    readonly property real activeWidth: Math.max(dot, 66 - Math.max(0, spaces.length - 1) * (dot + gap))
    implicitWidth: Math.max(108, spaces.length * (dot + gap) + 32) + theme.panelWing * 2
    implicitHeight: theme.panelHeight
    function activate(index) {
        if (index < 0 || index >= spaces.length) return;
        if (shell.fixture) { fixtureActive = index; shell.fixtureEvent("workspace", {id: spaces[index].id}); }
        else Hyprland.dispatch("hl.dsp.focus({ workspace = " + spaces[index].id + " })");
    }
    NotchSurface { anchors.fill: parent; wing: root.theme.panelWing; color: root.theme.background }
    Row {
        id: dots
        anchors.centerIn: parent
        spacing: root.gap
        Repeater {
            model: root.spaces
            Item {
                required property int index
                required property var modelData
                width: index === root.current ? root.activeWidth : root.dot
                height: 26
                Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.InOutCubic } }
                Rectangle { anchors.centerIn: parent; width: root.dot; height: root.dot; radius: height / 2; color: "#5e6074" }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.activate(parent.index) }
                Accessible.role: Accessible.Button
                Accessible.name: "Workspace " + modelData.id
                Accessible.onPressAction: root.activate(index)
                activeFocusOnTab: true
                Keys.onReturnPressed: root.activate(index)
                Keys.onSpacePressed: root.activate(index)
            }
        }
    }
    Rectangle {
        width: root.activeWidth; height: root.dot; radius: height / 2
        color: "#ffffff"
        y: (root.height - height) / 2
        x: dots.x + root.current * (root.dot + root.gap)
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.InOutCubic } }
        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.InOutCubic } }
    }
    property real scrollRemainder: 0
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: event => {
            const angle = event.angleDelta.y || event.angleDelta.x;
            root.scrollRemainder += angle || (event.pixelDelta.y || event.pixelDelta.x) * 2.4;
            if (Math.abs(root.scrollRemainder) < 120) return;
            root.activate(Math.max(0, Math.min(root.spaces.length - 1, root.current + (root.scrollRemainder > 0 ? -1 : 1))));
            root.scrollRemainder = 0;
        }
    }
}
