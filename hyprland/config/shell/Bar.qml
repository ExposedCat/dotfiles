import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Wayland

PanelWindow {
    id: bar
    required property var shell
    required property var theme
    readonly property var monitorInfo: shell.fixture ? null : Hyprland.monitorFor(screen)
    readonly property bool fullscreen: shell.fixture ? !!shell.fixtureData.fullscreen : !!(monitorInfo && monitorInfo.activeWorkspace && monitorInfo.activeWorkspace.hasFullscreen)
    readonly property bool idleHidden: shell.pillSuppressed || fullscreen
    // Explicitly opened views remain available while the idle pill is hidden.
    // Super holds still hide the current view until the modifier is released.
    readonly property bool hidden: shell.pillHidden || (!shell.panel && idleHidden)
    // Standalone views fade and slide at full size when there is no idle pill.
    // Keep their geometry and content until the closing animation finishes.
    property real hiddenPanelReveal: idleHidden && !!shell.panel ? 1 : 0
    Behavior on hiddenPanelReveal {
        enabled: bar.idleHidden
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }
    readonly property bool hiddenPanelVisible: idleHidden && (!!shell.panel || hiddenPanelReveal > 0)
    onHiddenPanelRevealChanged: {
        if (idleHidden && !shell.panel && hiddenPanelReveal === 0) { shownPanel = ""; launcherDragged = false; }
    }
    // The pill stays on the main screen; its workspace controls follow the
    // focused monitor. Feedback retains the monitor that emitted the switch.
    readonly property string workspaceOutput: !expanded && shell.osd.visible && shell.osd.kind === "workspace" && shell.osd.output
        ? shell.osd.output : shell.focusedScreen?.name || screen?.name || ""
    readonly property var spaces: shell.fixture
        ? (shell.fixtureData.workspacesByMonitor?.[workspaceOutput] || shell.fixtureData.workspaces || [{id: 1, active: true}, {id: 2, active: false}, {id: 3, active: false}])
        : Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor && w.monitor.name === workspaceOutput).sort((a,b) => a.id - b.id)
    readonly property bool expanded: hoverExpanded || shell.panel.length > 0 || trayMenu.visible
    readonly property string pillState: hidden ? "hidden" : shell.panel || feedbackKind || (expanded ? "expanded" : "compact")
    readonly property bool hasNotifications: shell.notifications.entries.length > 0
    // Track the pointer on the fixed native surface, not the animated header.
    readonly property bool pillHovered: hover.hovered && (
        (hover.point.position.x >= pill.x && hover.point.position.x < pill.x + pill.width
            && hover.point.position.y >= pill.y && hover.point.position.y < pill.y + headerHeight)
        || (expanded && !shell.panel && hover.point.position.x >= expansionTarget.x
            && hover.point.position.x < expansionTarget.x + expansionTarget.width
            && hover.point.position.y >= expansionTarget.y && hover.point.position.y < expansionTarget.y + expansionTarget.height))
    onPillHoveredChanged: {
        if (pillHovered && !hidden && !feedbackVisible && !suppressHover) { collapse.stop(); hoverExpanded = true; }
        else collapse.restart();
    }
    property bool hoverExpanded: false
    property bool suppressHover: false
    property string shownPanel: ""
    readonly property var paneNames: ["launcher", "portal", "credentials", "notifications", "bluetooth", "ethernet", "power", "media", "mixer", "system"]
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
        return ({launcher: launcherComponent, portal: portalComponent, credentials: credentialComponent, notifications: notificationsComponent, bluetooth: bluetoothComponent, ethernet: networkComponent, power: powerComponent, media: mediaComponent, mixer: mixerComponent, system: statsComponent})[name];
    }
    Timer { id: warm; interval: 100; onTriggered: { bar.retain("launcher"); bar.retain("media"); bar.retain("mixer"); } }
    Timer { id: unload; interval: 120000; onTriggered: { const keep = {}; for (const name of ["launcher", "media", "mixer"]) if (bar.retained[name]) keep[name] = true; bar.retained = keep; } }
    property real paneWidth: 620
    property real paneHeight: 480
    property real mediaHeight: 240
    property real systemHeight: 480
    property real networkHeight: 270
    property bool launcherDragged: false
    property point launcherPosition: Qt.point(0, 0)
    property point dragStart: Qt.point(0, 0)
    property point dragOrigin: Qt.point(0, 0)
    property bool dragPressed: false
    property var focusGrab: null
    readonly property bool pinnedLauncher: (shell.panel === "launcher" || (hiddenPanelVisible && shownPanel === "launcher")) && launcherDragged
    readonly property bool wantsFocusGrab: !!shell.panel && !hidden && !shell.captureActive && (!pinnedLauncher || dragPressed) && !centerFocus.editing
    readonly property bool nativeActive: !!bar.contentItem.Window.window && bar.contentItem.Window.window.active
    function beginLauncherDrag(x, y) {
        if (shell.panel !== "launcher") return;
        dragStart = Qt.point(x, y); dragOrigin = Qt.point(pill.x, pill.y); dragPressed = true;
    }
    function moveLauncherDrag(x, y) {
        if (!dragPressed || shell.panel !== "launcher") return;
        const dx = x - dragStart.x, dy = y - dragStart.y;
        if (!launcherDragged && Math.hypot(dx, dy) < 5) return;
        launcherPosition = Qt.point(Math.round(Math.max(12, Math.min(width - paneWidth - 12, dragOrigin.x + dx))),
                                  Math.round(Math.max(8, Math.min(height - paneHeight - 12, dragOrigin.y + dy))));
        launcherDragged = true;
    }
    function endLauncherDrag() { dragPressed = false; }
    function lostFocus() {
        if (shell.panel && !pinnedLauncher && !dragPressed && !hidden && !shell.captureActive) {
            suppressHover = true; hoverRelease.restart();
            dismiss(); hoverExpanded = false;
        }
    }
    function applicationFocused() { if (!shell.captureActive) focusLoss.restart(); }
    Component { id: panelFocusGrab; HyprlandFocusGrab {} }
    Component.onCompleted: {
        if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
            focusGrab = panelFocusGrab.createObject(bar, {windows: [bar, trayMenu]});
            focusGrab.cleared.connect(() => { if (bar.wantsFocusGrab) bar.lostFocus(); });
            if (wantsFocusGrab) armFocus.restart();
        }
    }
    onWantsFocusGrabChanged: {
        if (focusGrab) {
            if (wantsFocusGrab) armFocus.restart();
            else { armFocus.stop(); focusGrab.active = false; }
        }
    }
    Timer { id: armFocus; interval: 0; onTriggered: { if (bar.focusGrab && bar.wantsFocusGrab) bar.focusGrab.active = true; } }
    Timer { id: focusLoss; interval: 50; onTriggered: { if (!bar.nativeActive && !trayMenu.visible) bar.lostFocus(); } }
    Timer { id: hoverRelease; interval: 300; onTriggered: bar.suppressHover = false }
    onNativeActiveChanged: { if (!nativeActive && shell.panel && !shell.captureActive) focusLoss.restart(); }
    onMediaHeightChanged: { if (shell.panel === "media") selectPanel("media"); }
    onSystemHeightChanged: { if (shell.panel === "system") selectPanel("system"); }
    onNetworkHeightChanged: { if (shell.panel === "ethernet") selectPanel("ethernet"); }
    readonly property int headerHeight: 40
    readonly property int pillRadius: 20
    readonly property int sideInset: 20
    readonly property int groupSpacing: 24
    readonly property real compactContentWidth: timeButton.width + 14 + layoutLabel.width
    readonly property int notificationSpace: hasNotifications ? 30 : 0
    readonly property real compactWidth: Math.ceil((compactContentWidth + 36 + notificationSpace) / 2) * 2
    readonly property real leftContentWidth: compactContentWidth / 2 + 14 + dateLabel.width + workspaceControls.implicitWidth + (trayItems.count ? trayIcons.implicitWidth : 0) + sideInset
    // Reserve the indicator's slot while expanded so arrivals never retarget
    // the expansion animation, fade the controls, or move them under the mouse.
    readonly property real rightContentWidth: compactContentWidth / 2 + weekdayLabel.width - layoutLabel.width + 30 + appearanceButton.width + controlButtons.implicitWidth + sideInset
    readonly property real leftNeed: leftContentWidth + groupSpacing * (trayItems.count ? 2 : 1)
    // Each left spacer takes half the remaining left-hand room. Reserve room
    // for the matching right spacer too, without measuring its own stretched width.
    readonly property real rightNeed: trayItems.count ? 2 * Math.ceil(rightContentWidth) - Math.floor(leftContentWidth) : rightContentWidth + groupSpacing
    readonly property real controlsWidth: Math.ceil(Math.max(600, 2 * Math.max(leftNeed, rightNeed)) / 2) * 2
    readonly property real targetWidth: Math.min(width - 24, shell.panel || hiddenPanelVisible ? paneWidth : expanded ? controlsWidth : compactWidth + feedbackLeft + feedbackRight)
    readonly property real targetHeight: shell.panel || hiddenPanelVisible ? paneHeight : headerHeight
    // Animate position and size together, including the return from a drag.
    // Standalone views use the reveal animation instead of the compact morph.
    // Snap all painted coordinates to whole pixels to avoid text shimmer.
    readonly property rect targetGeometry: Qt.rect(
        pinnedLauncher ? launcherPosition.x : (width - targetWidth) / 2 + (hiddenPanelVisible ? 0 : (feedbackRight - feedbackLeft + (!expanded ? notificationSpace : 0)) / 2),
        pinnedLauncher ? launcherPosition.y : theme.panelGap, targetWidth, targetHeight)
    property rect animatedGeometry: targetGeometry
    Behavior on animatedGeometry {
        enabled: !bar.dragPressed && !bar.idleHidden
        PropertyAnimation { duration: 220; easing.type: Easing.InOutCubic }
    }
    readonly property rect pillGeometry: Qt.rect(pill.x, pill.y, pill.width, pill.height)
    readonly property rect paneGeometry: Qt.rect(pill.x + panelLoader.x, pill.y + panelLoader.y, panelLoader.width, panelLoader.height)
    readonly property var activePane: panelLoader.item
    readonly property real detailsOpacity: Math.min(1, Math.max(0, (pill.width - controlsWidth + 60) / 60))
    readonly property real workspaceInset: leftControls.x
    PillTheme { id: colors }
    TextMetrics { id: clockMetrics; font: colors.textFont; text: "00:00" }

    // This native surface never changes size or takes reserved app space.
    anchors { top: true; left: true; right: true }
    implicitHeight: screen ? screen.height : 1080
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "dotfiles-bar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: hidden || shell.captureActive ? WlrKeyboardFocus.None : ["launcher", "portal", "credentials", "media", "mixer", "system", "power", "ethernet", "bluetooth"].includes(shell.panel) ? WlrKeyboardFocus.OnDemand : shell.panel === "notifications" ? centerFocus.keyboardMode : WlrKeyboardFocus.None
    Region { id: pillInput; item: pill }
    // A fast pointer can reach the controls before the painted pill does.
    // Keep that destination interactive throughout hover expansion.
    Item {
        id: expansionTarget
        x: bar.targetGeometry.x; y: bar.targetGeometry.y
        width: bar.targetWidth; height: bar.headerHeight
    }
    Region { id: expansionInput; item: expansionTarget }
    Region { id: outsideInput; item: bar.contentItem }
    // Keep the native input region and focus grab intact until release. A fast
    // pointer can get ahead of the painted surface between rendering frames.
    mask: Region { regions: bar.hidden ? [] : bar.shell.panel && (!bar.pinnedLauncher || bar.dragPressed) ? [outsideInput] : bar.expanded && !bar.shell.panel ? [pillInput, expansionInput] : [pillInput] }
    ReplyFocus { id: centerFocus; available: bar.shell.panel === "notifications" && !bar.hidden && !bar.shell.captureActive; store: bar.shell.notifications; surface: "center"; targetWindow: bar }
    MouseArea {
        anchors.fill: parent
        enabled: bar.shell.panel.length > 0 && !bar.pinnedLauncher && !bar.dragPressed
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onPressed: bar.dismiss()
        onWheel: event => event.accepted = false
    }
    function dismiss() { endLauncherDrag(); shell.panel = ""; }
    function openPanel(name) { trayMenu.visible = false; shell.toggle(name); }
    property var portalPane: null
    property var credentialPane: null
    function selectPanel(name) {
        // Retain this geometry until the closing fade has finished. The popup's
        // layout must not be resized to the compact pill while still visible.
        const portalWidth = portalPane?.desiredWidth || (shell.portal.data.kind === "share" ? 680 : shell.portal.data.kind === "access" ? 440 : 560);
        paneWidth = Math.min(width - 24, name === "credentials" ? (credentialPane?.desiredWidth || 460) : name === "ethernet" ? 460 : name === "portal" ? portalWidth : name === "launcher" ? 560 : name === "mixer" ? 520 : name === "notifications" ? 1080 : 620);
        paneHeight = Math.min(height - 24, name === "credentials" ? (credentialPane?.desiredHeight || 340) : name === "portal" ? (portalPane?.desiredHeight || 428) : name === "launcher" ? 428 : name === "mixer" ? 136 : name === "notifications" ? 680 : name === "bluetooth" ? 500 : name === "ethernet" ? networkHeight : name === "media" ? mediaHeight : name === "system" ? systemHeight : 220);
        retain(name); shownPanel = name;
    }
    Connections {
        target: bar.portalPane
        function onDesiredWidthChanged() { if (bar.shell.panel === "portal") bar.selectPanel("portal"); }
        function onDesiredHeightChanged() { if (bar.shell.panel === "portal") bar.selectPanel("portal"); }
    }
    Connections {
        target: bar.credentialPane
        function onDesiredWidthChanged() { if (bar.shell.panel === "credentials") bar.selectPanel("credentials"); }
        function onDesiredHeightChanged() { if (bar.shell.panel === "credentials") bar.selectPanel("credentials"); }
    }
    onWidthChanged: { if (shell.panel) selectPanel(shell.panel); }
    onHeightChanged: { if (shell.panel) selectPanel(shell.panel); }
    Shortcut { sequence: "Escape"; enabled: !!bar.shell.panel && !bar.shell.captureActive; context: Qt.WindowShortcut; onActivated: bar.dismiss() }
    Connections {
        target: bar.shell
        function onCaptureActiveChanged() {
            focusLoss.stop();
            if (!bar.shell.captureActive && bar.shell.panel && !bar.hidden) {
                if (centerFocus.editing && centerFocus.grab) centerFocus.grab.active = true;
                if (["launcher", "portal", "credentials"].includes(bar.shell.panel) && panelLoader.item) panelLoader.item.focusSearch();
            }
        }
        function onPanelChanged() {
            focusLoss.stop();
            bar.dragPressed = false;
            if (bar.shell.panel) bar.launcherDragged = false;
            if (bar.shell.panel) {
                unload.stop();
                bar.selectPanel(bar.shell.panel);
                trayMenu.visible = false;
                if (["launcher", "portal", "credentials"].includes(bar.shell.panel)) { if (panelLoader.item) panelLoader.item.activate(); focusDelay.restart(); }
            } else {
                unload.restart();
                if (bar.launcherDragged) { bar.suppressHover = true; hoverRelease.restart(); }
                bar.hoverExpanded = !bar.suppressHover && bar.pillHovered;
                if (pill.height === bar.headerHeight) bar.shownPanel = "";
            }
        }
    }
    Connections {
        target: centerFocus.grab
        function onCleared() { if (centerFocus.editing) bar.lostFocus(); }
    }
    onHiddenChanged: {
        if (hidden) { trayMenu.visible = false; collapse.stop(); focusLoss.stop(); }
        else if (!shell.captureActive && ["launcher", "portal", "credentials"].includes(shell.panel) && panelLoader.item) panelLoader.item.focusSearch();
    }
    onFullscreenChanged: { if (fullscreen) hoverExpanded = false; }
    Timer { id: focusDelay; interval: 230; onTriggered: { if (!bar.shell.captureActive && ["launcher", "portal", "credentials"].includes(bar.shell.panel) && panelLoader.item) panelLoader.item.focusSearch(); } }
    Timer { id: collapse; interval: 240; onTriggered: { if (!bar.pillHovered && !bar.shell.panel && !trayMenu.visible && !bar.hidden) bar.hoverExpanded = false; } }
    TrayMenu { id: trayMenu; theme: colors; onVisibleChanged: { if (!visible && !bar.pillHovered) collapse.restart(); } }
    HoverHandler { id: hover; enabled: !bar.hidden }
    Item {
        id: pill
        objectName: "floatingPill"
        width: Math.round(bar.animatedGeometry.width / 2) * 2
        height: Math.round(bar.animatedGeometry.height)
        x: Math.round(bar.animatedGeometry.x)
        y: Math.round(bar.animatedGeometry.y)
        transform: Translate { y: bar.idleHidden ? Math.round(-12 * (1 - bar.hiddenPanelReveal)) : 0 }
        opacity: bar.shell.pillHidden ? 0 : bar.idleHidden ? bar.hiddenPanelReveal : 1
        onHeightChanged: { if (height === bar.headerHeight && !bar.shell.panel) { bar.shownPanel = ""; bar.launcherDragged = false; } }
        PillBackground { anchors.fill: parent; theme: colors; radius: bar.pillRadius }
        Item {
            anchors.fill: parent
            clip: true
            MouseArea { anchors.fill: parent; onWheel: event => event.accepted = false }
            Item {
                id: header
                objectName: "pillHeader"
                width: parent.width; height: bar.headerHeight
                visible: !bar.idleHidden
                opacity: bar.idleHidden || bar.shownPanel ? 0 : 1
                enabled: opacity > 0.95
                Behavior on opacity { enabled: !bar.idleHidden; NumberAnimation { duration: 100 } }
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
                        font: colors.textFont
                        color: colors.text
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bar.openPanel("notifications") }
                }
                Text {
                    id: dateLabel
                    width: Math.ceil(implicitWidth)
                    x: timeButton.x - width - 14; y: Math.round((bar.headerHeight - height) / 2)
                    text: Qt.formatDateTime(bar.shell.clock.date, "MM.dd")
                    font: colors.textFont
                    color: colors.secondary
                    opacity: bar.shell.panel === "launcher" ? 1 : bar.detailsOpacity
                    visible: opacity > 0
                }
                Text {
                    id: layoutLabel
                    width: Math.ceil(implicitWidth)
                    x: timeButton.x + timeButton.width + 14
                    y: Math.round((bar.headerHeight - height) / 2)
                    text: bar.shell.layoutLabel
                    font: colors.textFont
                    color: colors.secondary
                    opacity: 1 - bar.detailsOpacity
                    visible: opacity > 0
                }
                Text {
                    id: weekdayLabel
                    width: Math.ceil(implicitWidth)
                    x: timeButton.x + timeButton.width + 14; y: Math.round((bar.headerHeight - height) / 2)
                    text: Qt.formatDateTime(bar.shell.clock.date, "ddd")
                    font: colors.textFont
                    color: colors.secondary
                    opacity: bar.detailsOpacity
                    visible: opacity > 0
                }
                ShellButton {
                    id: notificationDot
                    objectName: "pillNotificationIndicator"
                    opacity: bar.hasNotifications ? 1 : 0
                    scale: opacity
                    visible: opacity > 0
                    enabled: bar.hasNotifications
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }
                    x: Math.round(weekdayLabel.x + layoutLabel.width + (weekdayLabel.width - layoutLabel.width) * bar.detailsOpacity + 12); y: 4
                    theme: colors; implicitWidth: 18; implicitHeight: 32
                    hint: "Notifications"; onClicked: bar.openPanel("notifications")
                    Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: colors.accent }
                }
                RowLayout {
                    id: leftControls
                    x: bar.sideInset; y: 0
                    width: Math.max(implicitWidth, dateLabel.x - x)
                    height: bar.headerHeight; spacing: 0
                    opacity: bar.shell.panel === "launcher" ? 0 : bar.detailsOpacity
                    enabled: opacity > 0.95
                    Row {
                        id: workspaceControls
                        Layout.alignment: Qt.AlignVCenter
                        height: bar.headerHeight; spacing: 8
                        WorkspaceDots { id: workspaceWidget; shell: bar.shell; theme: colors; spaces: bar.spaces; floating: true; implicitHeight: bar.headerHeight }
                        Item {
                            objectName: "pillScreenSharingIndicator"
                            visible: bar.shell.screenSharing
                            width: 36; height: bar.headerHeight
                            Accessible.role: Accessible.StaticText
                            Accessible.name: "Screen sharing active"
                            ShellIcon { anchors.centerIn: parent; name: "screen-share"; width: 21; height: 21 }
                        }
                    }
                    Item { id: workspaceTraySpacer; visible: trayItems.count > 0; Layout.fillWidth: true; Layout.minimumWidth: bar.groupSpacing }
                    Row {
                        id: trayIcons
                        Layout.alignment: Qt.AlignVCenter
                        height: 36; spacing: 2
                        visible: trayItems.count > 0
                        Repeater {
                            id: trayItems
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
                    }
                    Item { Layout.fillWidth: true; Layout.minimumWidth: bar.groupSpacing }
                }
                Row {
                    id: rightControls
                    objectName: "pillRightControls"
                    // Hold the row at its expanded screen position while the
                    // surface changes size, rather than following its edge.
                    x: Math.round((bar.width + bar.controlsWidth) / 2) - bar.sideInset - width - pill.x; y: 2
                    height: 36; spacing: 0
                    opacity: bar.shell.panel === "launcher" ? 0 : bar.detailsOpacity
                    enabled: opacity > 0.95
                    ShellButton {
                        id: appearanceButton; objectName: "pillAppearanceButton"
                        emberShell: bar.shell; theme: colors
                        icon: bar.shell.appearance.dark ? "moon" : "sun"
                        hint: bar.shell.appearance.error || (bar.shell.appearance.dark ? "Switch to light style" : "Switch to dark style")
                        enabled: bar.shell.appearance.available && !bar.shell.appearance.pending
                        onClicked: bar.shell.appearance.toggle()
                    }
                    Row {
                        id: controlButtons
                        objectName: "pillControlButtons"
                        height: 36; spacing: 2
                        ShellButton { objectName: "pillMusicButton"; visible: !!bar.shell.media.player; emberShell: bar.shell; theme: colors; icon: "music"; hint: "Now playing"; selected: bar.shell.panel === "media"; onClicked: bar.openPanel("media") }
                        ShellButton { emberShell: bar.shell; theme: colors; icon: bar.shell.audio.muted ? "volume-x" : "volume-2"; hint: "Sound"; selected: bar.shell.panel === "mixer"; onClicked: bar.openPanel("mixer"); onScrolled: delta => bar.shell.audio.adjust(delta > 0 ? 0.05 : -0.05) }
                        ShellButton { emberShell: bar.shell; theme: colors; icon: "activity"; hint: "System statistics"; selected: bar.shell.panel === "system"; onClicked: bar.openPanel("system") }
                        ShellButton { emberShell: bar.shell; theme: colors; icon: "ethernet-port"; hint: "Network"; selected: bar.shell.panel === "ethernet"; onClicked: bar.openPanel("ethernet") }
                        ShellButton { emberShell: bar.shell; theme: colors; icon: "bluetooth"; hint: "Bluetooth"; selected: bar.shell.panel === "bluetooth"; onClicked: bar.openPanel("bluetooth") }
                        ShellButton { emberShell: bar.shell; theme: colors; icon: "power"; hint: "Power"; selected: bar.shell.panel === "power"; onClicked: bar.openPanel("power") }
                    }
                }
            }
            Item {
                id: panelLoader
                readonly property int inset: ["launcher", "portal", "credentials"].includes(bar.shownPanel) ? 12 : 24
                x: bar.launcherDragged ? inset : Math.round((bar.width - bar.paneWidth) / 2) - pill.x + inset
                y: ["launcher", "portal", "credentials"].includes(bar.shownPanel) ? 8 : 16
                width: bar.paneWidth - inset * 2; height: bar.paneHeight - y - inset
                readonly property var item: bar.shownPanel ? paneSlots.itemAt(bar.paneNames.indexOf(bar.shownPanel))?.item || null : null
                Repeater {
                    id: paneSlots
                    model: bar.paneNames
                    Loader {
                        required property string modelData
                        anchors.fill: parent
                        active: !!bar.retained[modelData]
                        opacity: modelData === bar.shownPanel && (bar.shell.panel || bar.hiddenPanelVisible) && pill.height > bar.headerHeight + 30 ? 1 : 0
                        visible: opacity > 0
                        enabled: modelData === bar.shell.panel
                        // Fade the notification stack as one image so its back
                        // layers stay behind the front card during the fade.
                        layer.enabled: modelData === "notifications" && opacity > 0 && opacity < 1
                        Behavior on opacity {
                            // A view being replaced must disappear before its
                            // retained loader takes on the next view's size.
                            enabled: !bar.shell.panel || modelData === bar.shell.panel
                            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }
                        sourceComponent: bar.componentFor(modelData)
                        onLoaded: { if (modelData === "portal") bar.portalPane = item; if (modelData === "credentials") bar.credentialPane = item; if (["launcher", "portal", "credentials"].includes(modelData) && bar.shell.panel === modelData) { item.activate(); if (["portal", "credentials"].includes(modelData)) Qt.callLater(() => bar.selectPanel(modelData)); } }
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
        showing: bar.feedbackVisible && bar.shell.osd.kind === "workspace" && !bar.hidden
        x: bar.sideInset; y: 0
    }
    PillWing {
        id: valueWing; objectName: "valueWing"
        parent: header
        shell: bar.shell; theme: colors; spaces: bar.spaces
        showing: bar.feedbackVisible && bar.shell.osd.kind !== "workspace" && !bar.hidden
        x: Math.round((bar.width + bar.compactWidth) / 2) - pill.x - 4; y: 0
    }
    Component {
        id: launcherComponent
        LauncherPane {
            shell: bar.shell; theme: colors
            onDragStarted: (x, y) => bar.beginLauncherDrag(x, y)
            onDragMoved: (x, y) => bar.moveLauncherDrag(x, y)
            onDragFinished: bar.endLauncherDrag()
        }
    }
    Component { id: credentialComponent; CredentialPane { shell: bar.shell; theme: colors } }
    Component { id: portalComponent; PortalPane { shell: bar.shell; theme: colors } }
    Component { id: notificationsComponent; NotificationCenter { shell: bar.shell; theme: colors } }
    Component { id: bluetoothComponent; BluetoothMenu { shell: bar.shell; theme: colors } }
    Component {
        id: networkComponent
        EthernetMenu {
            shell: bar.shell; theme: colors
            onImplicitHeightChanged: bar.networkHeight = implicitHeight + 40
            Component.onCompleted: bar.networkHeight = implicitHeight + 40
        }
    }
    Component { id: powerComponent; PowerPane { shell: bar.shell; theme: colors } }
    Component {
        id: mediaComponent
        MediaPane {
            shell: bar.shell; theme: colors
            onImplicitHeightChanged: bar.mediaHeight = implicitHeight + 40
            Component.onCompleted: bar.mediaHeight = implicitHeight + 40
        }
    }
    Component { id: mixerComponent; MixerPane { shell: bar.shell; theme: colors } }
    Component {
        id: statsComponent
        StatsPane {
            shell: bar.shell; theme: colors
            onImplicitHeightChanged: bar.systemHeight = implicitHeight + 40
            Component.onCompleted: bar.systemHeight = implicitHeight + 40
        }
    }
    readonly property Item emberTarget: {
        if (hidden) return null;
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
        active: bar.shell.emberEnabled && !!target && !bar.hidden
    }
}
