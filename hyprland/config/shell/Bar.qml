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
    readonly property var spaces: shell.fixture ? (shell.fixtureData.workspaces || [{id: 1, active: true}, {id: 2, active: false}, {id: 3, active: false}]) : Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor && w.monitor.name === screen.name).sort((a,b) => a.id - b.id)
    readonly property bool expanded: hoverExpanded || shell.panel.length > 0 || trayMenu.visible
    readonly property string pillState: shell.pillHidden ? "hidden" : shell.panel || feedbackKind || (expanded ? "expanded" : "compact")
    readonly property bool hasNotifications: shell.notifications.entries.length > 0
    property bool hoverExpanded: false
    property string shownPanel: ""
    readonly property var paneNames: ["launcher", "notifications", "bluetooth", "ethernet", "power", "media", "mixer", "system"]
    property var retained: ({})
    readonly property string feedbackKind: !shell.panel && !expanded && shell.osd.visible ? "osd" : ""
    readonly property bool feedbackVisible: feedbackKind.length > 0
    readonly property real feedbackLeft: feedbackVisible && shell.osd.kind === "workspace" ? workspaceWing.naturalWidth + 14 : 0
    readonly property real feedbackRight: feedbackVisible && shell.osd.kind !== "workspace" ? valueWing.naturalWidth + 18 : 0
    onHoverExpandedChanged: { if (hoverExpanded) warm.restart(); }
    function retain(name) {
        if (retained[name]) return;
        const next = Object.assign({}, retained); next[name] = true; retained = next;
    }
    function componentFor(name) {
        return ({launcher: launcherComponent, notifications: notificationsComponent, bluetooth: bluetoothComponent, ethernet: networkComponent, power: powerComponent, media: mediaComponent, mixer: mixerComponent, system: statsComponent})[name];
    }
    Timer { id: warm; interval: 100; onTriggered: { bar.retain("launcher"); bar.retain("media"); bar.retain("mixer"); } }
    Timer { id: unload; interval: 120000; onTriggered: { const keep = {}; for (const name of ["launcher", "media", "mixer"]) if (bar.retained[name]) keep[name] = true; bar.retained = keep; } }
    property real paneWidth: 620
    property real paneHeight: 480
    readonly property int headerHeight: 40
    readonly property int pillRadius: 20
    readonly property int sideInset: 20
    readonly property real compactContentWidth: timeButton.width + 14 + layoutLabel.width + (hasNotifications ? 30 : 0)
    readonly property real compactWidth: Math.ceil((compactContentWidth + 36) / 2) * 2
    readonly property real leftNeed: compactContentWidth / 2 + 14 + dateLabel.width + 24 + leftControls.width + sideInset
    readonly property real rightNeed: compactContentWidth / 2 + 24 + rightControls.width + sideInset
    readonly property real controlsWidth: Math.ceil(Math.max(600, 2 * Math.max(leftNeed, rightNeed)) / 2) * 2
    readonly property real targetWidth: Math.min(width - 24, shell.panel ? paneWidth : expanded ? controlsWidth : compactWidth + feedbackLeft + feedbackRight)
    readonly property real targetHeight: shell.panel ? paneHeight : headerHeight
    // A single interpolated rectangle keeps width and height on the same frame.
    // Snap all painted coordinates to whole pixels to avoid text shimmer.
    property rect animatedGeometry: Qt.rect((feedbackRight - feedbackLeft) / 2, 0, targetWidth, targetHeight)
    Behavior on animatedGeometry { PropertyAnimation { duration: 220; easing.type: Easing.InOutCubic } }
    readonly property rect pillGeometry: Qt.rect(pill.x, pill.y, pill.width, pill.height)
    readonly property rect paneGeometry: Qt.rect(pill.x + panelLoader.x, pill.y + panelLoader.y, panelLoader.width, panelLoader.height)
    readonly property var activePane: panelLoader.item
    readonly property real detailsOpacity: Math.min(1, Math.max(0, (pill.width - controlsWidth + 60) / 60))
    readonly property real workspaceInset: leftControls.x
    PillTheme { id: colors }
    TextMetrics { id: clockMetrics; font.family: colors.fontFamily; font.pixelSize: colors.bodySize; text: "00:00" }

    // This native surface never changes size or takes reserved app space.
    anchors { top: true; left: true; right: true }
    implicitHeight: screen ? screen.height : 1080
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "dotfiles-bar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shell.pillHidden ? WlrKeyboardFocus.None : shell.panel === "launcher" ? WlrKeyboardFocus.Exclusive : ["media", "mixer", "system", "power", "ethernet", "bluetooth"].includes(shell.panel) ? WlrKeyboardFocus.OnDemand : shell.panel === "notifications" ? centerFocus.keyboardMode : WlrKeyboardFocus.None
    Region { id: pillInput; item: pill }
    Region { id: outsideInput; item: bar.contentItem }
    mask: Region { regions: bar.shell.pillHidden ? [] : bar.shell.panel ? [outsideInput] : [pillInput] }
    ReplyFocus { id: centerFocus; available: bar.shell.panel === "notifications" && !bar.shell.pillHidden; store: bar.shell.notifications; surface: "center"; targetWindow: bar }
    MouseArea {
        anchors.fill: parent
        enabled: bar.shell.panel.length > 0
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onPressed: bar.dismiss()
        onWheel: event => event.accepted = false
    }
    function dismiss() { shell.panel = ""; }
    function openPanel(name) { trayMenu.visible = false; shell.toggle(name); }
    function selectPanel(name) {
        // Retain this geometry until the closing fade has finished. The popup's
        // layout must not be resized to the compact pill while still visible.
        paneWidth = Math.min(width - 24, name === "launcher" ? 620 : Math.max(controlsWidth, name === "notifications" ? 1180 : 620));
        paneHeight = Math.min(height - 24, headerHeight + (name === "launcher" ? 440 : name === "notifications" ? 820 : name === "bluetooth" ? 500 : name === "ethernet" ? 270 : name === "media" ? 340 : name === "mixer" ? 540 : name === "system" ? 440 : 220));
        retain(name); shownPanel = name;
    }
    Connections {
        target: bar.shell
        function onPanelChanged() {
            if (bar.shell.panel) {
                unload.stop();
                bar.selectPanel(bar.shell.panel);
                trayMenu.visible = false;
                if (bar.shell.panel === "launcher") { if (panelLoader.item) panelLoader.item.activate(); focusDelay.restart(); }
            } else {
                unload.restart();
                bar.hoverExpanded = hover.hovered;
                if (pill.height === bar.headerHeight) bar.shownPanel = "";
            }
        }
        function onPillHiddenChanged() {
            if (bar.shell.pillHidden) { trayMenu.visible = false; collapse.stop(); }
            else if (bar.shell.panel === "launcher" && panelLoader.item) panelLoader.item.focusSearch();
        }
    }
    Timer { id: focusDelay; interval: 230; onTriggered: { if (bar.shell.panel === "launcher" && panelLoader.item) panelLoader.item.focusSearch(); } }
    Timer { id: collapse; interval: 240; onTriggered: { if (!hover.hovered && !bar.shell.panel && !trayMenu.visible && !bar.shell.pillHidden) bar.hoverExpanded = false; } }
    TrayMenu { id: trayMenu; theme: colors; onVisibleChanged: { if (!visible && !hover.hovered) collapse.restart(); } }
    Item {
        id: pill
        objectName: "floatingPill"
        width: Math.round(bar.animatedGeometry.width / 2) * 2
        height: Math.round(bar.animatedGeometry.height)
        x: Math.round((bar.width - width) / 2 + bar.animatedGeometry.x); y: 12
        opacity: bar.shell.pillHidden ? 0 : 1
        onHeightChanged: { if (height === bar.headerHeight && !bar.shell.panel) bar.shownPanel = ""; }
        PillBackground { anchors.fill: parent; theme: colors; radius: bar.pillRadius }
        Item {
            anchors.fill: parent
            clip: true
            MouseArea { anchors.fill: parent; onWheel: event => event.accepted = false }
            Item {
                id: header
                width: parent.width; height: bar.headerHeight
                opacity: 1
                enabled: true
                Behavior on opacity { NumberAnimation { duration: 100 } }
                HoverHandler {
                    id: hover
                    onHoveredChanged: {
                        if (hovered && !bar.shell.pillHidden && !bar.feedbackVisible) { collapse.stop(); bar.hoverExpanded = true; }
                        else collapse.restart();
                    }
                }
                Item {
                    id: timeButton
                    width: Math.ceil(clockMetrics.width) + 2; height: bar.headerHeight
                    // Date and wings appear around the stationary clock.
                    x: Math.round((bar.width - bar.compactContentWidth) / 2) - pill.x
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Calendar and notifications"
                    Accessible.onPressAction: bar.openPanel("notifications")
                    Keys.onReturnPressed: bar.openPanel("notifications")
                    Keys.onSpacePressed: bar.openPanel("notifications")
                    Text {
                        x: Math.round((parent.width - width) / 2); y: Math.round((parent.height - height) / 2)
                        text: Qt.formatDateTime(bar.shell.clock.date, "hh:mm")
                        font.family: colors.fontFamily; font.weight: colors.fontWeight; font.pixelSize: colors.bodySize; font.features: ({"tnum": 1})
                        color: colors.text
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bar.openPanel("notifications") }
                }
                Text {
                    id: dateLabel
                    width: Math.ceil(implicitWidth)
                    x: timeButton.x - width - 14; y: Math.round((bar.headerHeight - height) / 2)
                    text: Qt.formatDateTime(bar.shell.clock.date, "MMM d, ddd")
                    font.family: colors.fontFamily; font.weight: colors.fontWeight; font.pixelSize: colors.bodySize
                    color: colors.secondary
                    opacity: bar.shell.panel === "launcher" ? 1 : bar.detailsOpacity
                    visible: opacity > 0
                }
                Text {
                    id: layoutLabel
                    width: Math.ceil(implicitWidth)
                    x: timeButton.x + timeButton.width + 14; y: Math.round((bar.headerHeight - height) / 2)
                    text: bar.shell.layoutLabel
                    font.family: colors.fontFamily; font.weight: colors.fontWeight; font.pixelSize: colors.bodySize
                    color: colors.secondary
                }
                ShellButton {
                    id: notificationDot
                    objectName: "pillNotificationIndicator"
                    visible: bar.hasNotifications
                    x: layoutLabel.x + layoutLabel.width + 12; y: 4
                    theme: colors; implicitWidth: 18; implicitHeight: 32
                    hint: "Notifications"; onClicked: bar.openPanel("notifications")
                    Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: colors.accent }
                }
                Row {
                    id: leftControls
                    x: bar.sideInset; y: 0
                    height: bar.headerHeight; spacing: 8
                    opacity: bar.shell.panel === "launcher" ? 0 : bar.detailsOpacity
                    enabled: opacity > 0.95
                    WorkspaceDots { id: workspaceWidget; shell: bar.shell; theme: colors; spaces: bar.spaces; floating: true; implicitHeight: bar.headerHeight }
                    ShellButton { y: 2; visible: bar.shell.recording; theme: colors; icon: "circle-dot"; danger: true; hint: "Stop recording"; onClicked: bar.shell.desktop("record") }
                }
                Row {
                    id: rightControls
                    x: Math.round(parent.width - bar.sideInset - width); y: 2
                    height: 36; spacing: 2
                    opacity: bar.shell.panel === "launcher" ? 0 : bar.detailsOpacity
                    enabled: opacity > 0.95
                    Repeater {
                        model: bar.shell.fixture ? [] : SystemTray.items
                        Item {
                            id: tray
                            required property var modelData
                            implicitWidth: 34; implicitHeight: 36
                            Image { anchors.centerIn: parent; width: 18; height: 18; sourceSize.width: 18; sourceSize.height: 18; source: tray.modelData.icon }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
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
                    ShellButton { emberShell: bar.shell; theme: colors; icon: "music"; hint: "Now playing"; selected: bar.shell.panel === "media"; onClicked: bar.openPanel("media") }
                    ShellButton { emberShell: bar.shell; theme: colors; icon: bar.shell.audio.muted ? "volume-x" : "volume-2"; hint: "Sound and brightness"; selected: bar.shell.panel === "mixer"; onClicked: bar.openPanel("mixer"); onScrolled: delta => bar.shell.audio.adjust(delta > 0 ? 0.05 : -0.05) }
                    ShellButton { emberShell: bar.shell; theme: colors; icon: "activity"; hint: "System statistics"; selected: bar.shell.panel === "system"; onClicked: bar.openPanel("system") }
                    ShellButton { emberShell: bar.shell; theme: colors; icon: "ethernet-port"; hint: "Network"; selected: bar.shell.panel === "ethernet"; onClicked: bar.openPanel("ethernet") }
                    ShellButton { emberShell: bar.shell; theme: colors; icon: "bluetooth"; hint: "Bluetooth"; selected: bar.shell.panel === "bluetooth"; onClicked: bar.openPanel("bluetooth") }
                    ShellButton { emberShell: bar.shell; theme: colors; icon: "power"; hint: "Power"; selected: bar.shell.panel === "power"; onClicked: bar.openPanel("power") }
                }
                ShellButton {
                    x: parent.width - width - 10; y: 2
                    visible: bar.shell.panel === "launcher"
                    theme: colors; icon: "x"; hint: "Close launcher"; onClicked: bar.dismiss()
                }
            }
            Item {
                id: panelLoader
                x: Math.round((bar.width - bar.paneWidth) / 2) - pill.x + 24
                y: bar.headerHeight + 16
                width: bar.paneWidth - 48; height: bar.paneHeight - y - 24
                readonly property var item: bar.shownPanel ? paneSlots.itemAt(bar.paneNames.indexOf(bar.shownPanel))?.item || null : null
                Repeater {
                    id: paneSlots
                    model: bar.paneNames
                    Loader {
                        required property string modelData
                        anchors.fill: parent
                        active: !!bar.retained[modelData]
                        opacity: modelData === bar.shownPanel && bar.shell.panel && pill.height > bar.headerHeight + 30 ? 1 : 0
                        visible: opacity > 0
                        enabled: modelData === bar.shell.panel
                        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        sourceComponent: bar.componentFor(modelData)
                        onLoaded: { if (modelData === "launcher" && bar.shell.panel === "launcher") item.activate(); }
                    }
                }
            }

        }
        Keys.onEscapePressed: bar.dismiss()
    }
    PillWing {
        id: workspaceWing; objectName: "workspaceWing"
        parent: header
        shell: bar.shell; theme: colors; spaces: bar.spaces; workspace: true
        showing: bar.feedbackVisible && bar.shell.osd.kind === "workspace" && !bar.shell.pillHidden
        x: bar.sideInset; y: 0
    }
    PillWing {
        id: valueWing; objectName: "valueWing"
        parent: header
        shell: bar.shell; theme: colors; spaces: bar.spaces
        showing: bar.feedbackVisible && bar.shell.osd.kind !== "workspace" && !bar.shell.pillHidden
        x: Math.round((bar.width + bar.compactWidth) / 2) - pill.x - 4; y: 0
    }
    Component { id: launcherComponent; LauncherPane { shell: bar.shell; theme: colors } }
    Component { id: notificationsComponent; NotificationCenter { shell: bar.shell; theme: colors } }
    Component { id: bluetoothComponent; BluetoothMenu { shell: bar.shell; theme: colors } }
    Component { id: networkComponent; EthernetMenu { shell: bar.shell; theme: colors } }
    Component { id: powerComponent; PowerPane { shell: bar.shell; theme: colors } }
    Component { id: mediaComponent; MediaPane { shell: bar.shell; theme: colors } }
    Component { id: mixerComponent; MixerPane { shell: bar.shell; theme: colors } }
    Component { id: statsComponent; StatsPane { shell: bar.shell; theme: colors } }
    readonly property Item emberTarget: {
        if (shell.pillHidden) return null;
        if (feedbackVisible) return shell.osd.kind === "workspace" ? workspaceWing.workspaceIndicator.emberSlot : null;
        if (!expanded) return null;
        if (shell.panel) return panelLoader.item?.emberTarget || null;
        return workspaceWidget.emberSlot;
    }
    property alias ember: ember
    Ember {
        id: ember
        parent: pill
        anchors.fill: parent
        clip: true
        z: 10
        target: bar.emberTarget
        active: bar.shell.emberEnabled && !!target && !bar.shell.pillHidden
    }
}
