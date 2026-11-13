import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Wayland

PanelWindow {
    id: bar
    required property var shell
    required property var theme
    readonly property var monitor: shell.fixture ? null : Hyprland.monitorFor(screen)
    readonly property var spaces: shell.fixture ? (shell.fixtureData.workspaces || [{id: 1, active: true}, {id: 2, active: false}, {id: 3, active: false}]) : Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor && w.monitor.name === screen.name).sort((a,b) => a.id - b.id)
    visible: dialog.visible || !monitor || !monitor.activeWorkspace || !monitor.activeWorkspace.hasFullscreen
    onVisibleChanged: if (!visible) trayMenu.visible = false
    anchors { top: true; left: true; right: true }
    // Popups share this persistent native surface with their original buttons.
    // Keep the native surface geometry fixed too: resizing it can reset hover.
    implicitHeight: screen ? screen.height : 1080
    exclusiveZone: theme.panelHeight + theme.panelGap
    color: "transparent"
    WlrLayershell.namespace: "dotfiles-bar"
    WlrLayershell.keyboardFocus: dialog.keyboardMode
    // Only the drops accept input. The empty panel area belongs to the desktop.
    Region { id: leftInput; item: leftWidgets }
    Region { id: clockInput; item: clockDrop }
    Region { id: bubbleInput; item: notificationBubble.bubbleItem }
    Region { id: rightInput; item: rightWidgets }
    Region { id: popupInput; item: bar.contentItem }
    mask: Region { regions: dialog.visible ? [popupInput] : [leftInput, clockInput, bubbleInput, rightInput] }
    MouseArea {
        anchors.fill: parent
        z: -2
        enabled: dialog.visible && dialog.expanded
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onPressed: bar.shell.panel = ""
        onWheel: event => event.accepted = false
    }
    // The original controls stay above the moving outline throughout a switch.
    Dialogs { id: dialog; z: -1; shell: bar.shell; theme: bar.theme; nativeWindow: bar }
    function openPanel(name, button) {
        trayMenu.visible = false;
        const point = button.mapToItem(bar.contentItem, 0, 0);
        bar.shell.toggle(name, bar.screen, point.x, button.width);
    }
    TrayMenu { id: trayMenu; theme: bar.theme }
    RowLayout {
        id: leftWidgets
        anchors { left: parent.left; top: parent.top; leftMargin: 6 }
        spacing: -24
        WorkspaceDots { shell: bar.shell; theme: bar.theme; spaces: bar.spaces }
        PanelDrop { visible: bar.shell.recording; theme: bar.theme; icon: "circle-dot"; text: "REC"; danger: true; hint: "Stop recording · Ctrl+Shift+Alt+R"; onClicked: bar.shell.desktop("record") }
    }
    PanelDrop {
        id: clockDrop
        horizontalPadding: 24
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
        theme: bar.theme; text: Qt.formatDateTime(bar.shell.clock.date, "d MMM  ·  hh:mm")
        hint: "Calendar and notifications"
        onClicked: bar.openPanel("notifications", this)
    }
    NotificationIndicator {
        id: notificationBubble
        x: clockDrop.x; sourceWidth: clockDrop.width; sourceRight: clockDrop.bodyRightEdge
        height: bar.height; theme: bar.theme
        present: bar.shell.notifications.entries.length > 0
        onClicked: bar.openPanel("notifications", clockDrop)
    }
    RowLayout {
        id: rightWidgets
        anchors { right: parent.right; top: parent.top; rightMargin: 6 }
        spacing: -24
        Repeater {
            model: bar.shell.fixture ? [] : SystemTray.items
            Item {
                id: tray
                required property var modelData
                implicitWidth: 50 + bar.theme.panelWing * 2; implicitHeight: bar.theme.panelHeight
                NotchSurface { anchors.fill: parent; wing: bar.theme.panelWing; color: bar.theme.background }
                Image { anchors.centerIn: parent; width: 18; height: 18; sourceSize.width: 18; sourceSize.height: 18; source: tray.modelData.icon }
                MouseArea {
                    id: pointer
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: event => {
                        if (event.button === Qt.RightButton || tray.modelData.onlyMenu) {
                            const point = tray.mapToItem(bar.contentItem, 0, tray.height);
                            bar.shell.panel = "";
                            trayMenu.open(tray.modelData, bar, point.x, point.y, tray.width);
                        } else if (event.button === Qt.MiddleButton) tray.modelData.secondaryActivate();
                        else tray.modelData.activate();
                    }
                    onWheel: event => tray.modelData.scroll(event.angleDelta.y, false)
                }
            }
        }
        PanelDrop { visible: bar.shell.audio.available && (bar.shell.audio.muted || bar.shell.audio.volume <= 0.0001); theme: bar.theme; icon: "volume-x"; hint: "Sound off"; onClicked: bar.shell.audio.toggleMute(); onScrolled: delta => bar.shell.audio.adjust(delta > 0 ? 0.05 : -0.05) }
        PanelDrop { theme: bar.theme; text: bar.shell.layoutLabel; hint: "Keyboard layout" }
        PanelDrop { id: ethernetDrop; theme: bar.theme; icon: "ethernet-port"; hint: "Ethernet"; onClicked: bar.openPanel("ethernet", this) }
        PanelDrop { id: bluetoothDrop; theme: bar.theme; icon: "bluetooth"; hint: "Bluetooth"; onClicked: bar.openPanel("bluetooth", this) }
        PanelDrop { id: powerDrop; theme: bar.theme; icon: "power"; hint: "Power menu · Super+M"; onClicked: bar.openPanel("power", this) }
    }
    // Keyboard/IPC opens use the same geometry as clicking the drop.
    Connections {
        target: bar.shell
        function onPanelChanged() {
            if (!bar.shell.panel) return;
            const button = bar.shell.panel === "notifications" ? clockDrop : bar.shell.panel === "power" ? powerDrop : bar.shell.panel === "bluetooth" ? bluetoothDrop : ethernetDrop;
            bar.shell.panelOriginX = button.mapToItem(bar.contentItem, 0, 0).x;
            bar.shell.panelOriginWidth = button.width;
        }
    }
}
