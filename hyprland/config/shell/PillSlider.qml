import QtQuick
import QtQuick.Controls

Slider {
    id: root
    property real backendValue: 0
    property bool muted: false
    property var emberShell: null
    readonly property Item emberSlot: thumbSlot
    readonly property bool emphasized: enabled && (hovered || pressed || visualFocus)
    implicitHeight: 26
    hoverEnabled: true
    Binding {
        target: root
        property: "value"
        value: root.backendValue
        when: !root.pressed
        restoreMode: Binding.RestoreNone
    }
    background: Item {
        x: root.leftPadding; width: root.availableWidth
        y: root.topPadding; height: root.availableHeight
        readonly property real center: root.visualPosition * (width - root.handle.width) + root.handle.width / 2
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.center - 5)
            height: root.emphasized ? 15 : 12
            radius: Math.min(width, height) / 2
            color: "#6be4cdb8"
            gradient: root.muted ? null : progressGradient
            Gradient {
                id: progressGradient
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#b77560" }
                GradientStop { position: 0.8; color: "#eeb08d" }
                GradientStop { position: 1; color: "#f6c8a8" }
            }
            Behavior on height { NumberAnimation { duration: 150 } }
        }
        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: Math.max(0, parent.width - parent.center - 5)
            height: root.emphasized ? 11 : 8
            radius: Math.min(width, height) / 2
            color: "#29e6bcaa"
            Behavior on height { NumberAnimation { duration: 150 } }
        }
    }
    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
        width: root.visualFocus ? 4 : 3
        height: root.emphasized ? 19 : 15
        radius: width / 2
        color: root.visualFocus ? "#fff4ec" : "#f6e1d4"
        EmberSlot {
            id: thumbSlot
            anchors.fill: parent
            shell: root.emberShell
            shapeOpacity: 0
        }
        Behavior on height { NumberAnimation { duration: 150 } }
    }
    HoverHandler { cursorShape: root.enabled ? Qt.SizeHorCursor : Qt.ArrowCursor }
}
