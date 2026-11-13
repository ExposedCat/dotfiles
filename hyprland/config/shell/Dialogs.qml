import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Item {
    id: window
    required property var shell
    required property var theme
    required property var nativeWindow
    property alias shown: motion.shown
    property alias confirmAction: motion.confirmAction
    property alias expanded: motion.expanded
    property alias progress: motion.progress
    property alias animationDuration: motion.animationDuration
    property alias originX: motion.originX
    property alias originWidth: motion.originWidth
    property alias targetX: motion.targetX
    property alias targetWidth: motion.targetWidth
    property alias targetHeight: motion.targetHeight
    property alias requestedHeight: motion.requestedHeight
    property alias moving: motion.moving
    readonly property real bubbleTop: theme.panelHeight + theme.panelGap
    PopupTransition {
        id: motion
        shell: window.shell; theme: window.theme
        screenWidth: window.nativeWindow.screen ? window.nativeWindow.screen.width : 1920
        screenHeight: window.nativeWindow.screen ? window.nativeWindow.screen.height : 1080
    }
    // Render the original drop once before the first opening animation.
    Connections {
        target: window.Window.window
        function onFrameSwapped() { motion.frameReady() }
    }
    visible: shown.length > 0
    anchors { top: parent.top; left: parent.left; right: parent.right }
    implicitHeight: Math.ceil(bubbleTop + Math.max(targetHeight, requestedHeight))
    readonly property int keyboardMode: visible && shown === "notifications" ? centerFocus.keyboardMode : WlrKeyboardFocus.None
    ReplyFocus { id: centerFocus; store: window.shell.notifications; surface: "center"; targetWindow: window.nativeWindow }
    PopupBubble {
        id: surface
        anchors.fill: parent
        originX: window.originX; originWidth: window.originWidth
        panelHeight: window.theme.panelHeight
        wing: window.theme.panelWing
        targetRect: Qt.rect(window.targetX, window.bubbleTop, window.targetWidth, window.targetHeight)
        progress: window.progress
        color: window.theme.background
    }
    Item {
        id: popupViewport
        x: surface.bodyLeft; y: surface.bodyTop
        width: surface.bodyRight - surface.bodyLeft
        height: surface.bodyHeight
        clip: true
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: event => event.accepted = false }
        Item {
            x: window.targetX + 24 - popupViewport.x; y: 22
            width: window.targetWidth - 48
            height: window.targetHeight - 44
            opacity: Math.max(0, (window.progress - 0.12) / 0.88)
            transform: Scale {
                origin.x: window.originX + window.originWidth / 2 - window.targetX - 24
                origin.y: -22
                xScale: window.progress; yScale: window.progress
            }
            visible: opacity > 0
            enabled: window.expanded && window.progress > 0.95 && !window.moving
            NotificationCenter {
                anchors.fill: parent; shell: window.shell; theme: window.theme
                opacity: window.shown === "notifications" ? 1 : 0
                visible: opacity > 0; enabled: window.shown === "notifications"
                Behavior on opacity { NumberAnimation { duration: window.animationDuration; easing.type: Easing.InOutCubic } }
            }
            BluetoothMenu {
                id: bluetooth; anchors.fill: parent; shell: window.shell; theme: window.theme
                opacity: window.shown === "bluetooth" ? 1 : 0
                visible: opacity > 0; enabled: window.shown === "bluetooth"
                Behavior on opacity { NumberAnimation { duration: window.animationDuration; easing.type: Easing.InOutCubic } }
            }
            EthernetMenu {
                id: ethernet; width: parent.width; shell: window.shell; theme: window.theme
                opacity: window.shown === "ethernet" ? 1 : 0
                visible: opacity > 0; enabled: window.shown === "ethernet"
                Behavior on opacity { NumberAnimation { duration: window.animationDuration; easing.type: Easing.InOutCubic } }
            }
            ColumnLayout {
                opacity: window.shown === "power" ? 1 : 0
                visible: opacity > 0; enabled: window.shown === "power"
                Behavior on opacity { NumberAnimation { duration: window.animationDuration; easing.type: Easing.InOutCubic } }
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
                spacing: 12
                Repeater {
                    model: [
                        [{id: "lock", title: "Lock", icon: "lock-keyhole"}, {id: "suspend", title: "Suspend", icon: "moon"}],
                        [{id: "logout", title: "Log out", icon: "log-out"}, {id: "reboot", title: "Restart", icon: "rotate-cw"}, {id: "poweroff", title: "Shut down", icon: "power"}]
                    ]
                    RowLayout {
                        required property var modelData
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12
                        Repeater {
                            model: modelData
                            ShellButton {
                                required property var modelData
                                implicitWidth: 64; implicitHeight: 60; radius: 18
                                theme: window.theme; icon: modelData.icon; iconSize: 28
                                hint: (window.confirmAction === modelData.id ? "Confirm " : "") + modelData.title
                                selected: window.confirmAction === modelData.id
                                color: selected ? window.theme.border : window.theme.surface
                                danger: ["logout", "reboot", "poweroff"].includes(modelData.id)
                                onClicked: {
                                    if (danger && window.confirmAction !== modelData.id) window.confirmAction = modelData.id;
                                    else { window.shell.power(modelData.id); window.shell.panel = "" }
                                }
                            }
                        }
                    }
                }
                Text { font.family: window.theme.fontFamily; font.weight: window.theme.fontWeight; font.pixelSize: window.theme.bodySize; text: window.shell.actionError; visible: text.length > 0; color: window.theme.red; wrapMode: Text.Wrap; Layout.preferredWidth: 228 }
            }
        }
    }
}
