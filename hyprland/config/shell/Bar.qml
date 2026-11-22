import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: bar
    required property var shell
    required property var theme
    readonly property alias pillTheme: colors
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
    readonly property bool popupOpen: expanded && !shell.panel && !hiddenPanelVisible
    readonly property point pointerPosition: hover.point.position
    readonly property string pillState: hidden ? "hidden" : shell.panel || feedbackKind || (expanded ? "expanded" : "compact")
    // Track the pointer on the fixed native surface, not the animated header.
    readonly property bool pillHovered: hover.hovered && (
        (hover.point.position.x >= pill.x && hover.point.position.x < pill.x + pill.width
            && hover.point.position.y >= pill.y && hover.point.position.y < pill.y + headerHeight)
        || (popupOpen && hover.point.position.x >= expansionTarget.x
            && hover.point.position.x < expansionTarget.x + expansionTarget.width
            && hover.point.position.y >= expansionTarget.y && hover.point.position.y < expansionTarget.y + expansionTarget.height))
    onPillHoveredChanged: {
        if (pillHovered && !hidden && !feedbackVisible && !suppressHover) { collapse.stop(); hoverExpanded = true; }
        else collapse.restart();
    }
    property bool hoverExpanded: false
    property bool suppressHover: false
    property string shownPanel: ""
    readonly property var paneNames: ["launcher", "portal", "credentials", "authentication", "notifications", "calendar", "bluetooth", "ethernet", "power", "media", "mixer", "system", "weather"]
    readonly property bool paneHasSearch: ["launcher", "portal", "credentials", "authentication", "weather"].includes(shell.panel)
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
        return ({launcher: launcherComponent, portal: portalComponent, credentials: credentialComponent, authentication: authenticationComponent, notifications: notificationsComponent, calendar: calendarComponent, bluetooth: bluetoothComponent, ethernet: networkComponent, power: powerComponent, media: mediaComponent, mixer: mixerComponent, system: statsComponent, weather: weatherComponent})[name];
    }
    Timer { id: warm; interval: 100; onTriggered: { bar.retain("launcher"); bar.retain("media"); bar.retain("mixer"); } }
    Timer { id: unload; interval: 120000; onTriggered: { const keep = {}; for (const name of ["launcher", "media", "mixer"]) if (bar.retained[name]) keep[name] = true; bar.retained = keep; } }
    property real paneWidth: 620
    property real paneHeight: 480
    property real calendarHeight: 660
    property real mediaHeight: 240
    property real systemHeight: 480
    property real weatherHeight: 220
    property real networkHeight: 270
    property real bluetoothHeight: 340
    property bool launcherDragged: false
    property point launcherPosition: Qt.point(0, 0)
    property point dragStart: Qt.point(0, 0)
    property point dragOrigin: Qt.point(0, 0)
    property bool dragPressed: false
    property var focusGrab: null
    readonly property bool pinnedLauncher: (shell.panel === "launcher" || (hiddenPanelVisible && shownPanel === "launcher")) && launcherDragged
    readonly property bool wantsFocusGrab: !!shell.panel && shell.panel !== "authentication" && !hidden && !shell.captureActive && (!pinnedLauncher || dragPressed) && !centerFocus.editing
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
        // Polkit owns exclusive keyboard focus; its handoff must not dismiss it.
        if (shell.panel === "authentication") return;
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
    onCalendarHeightChanged: { if (shell.panel === "calendar") selectPanel("calendar"); }
    onSystemHeightChanged: { if (shell.panel === "system") selectPanel("system"); }
    onNetworkHeightChanged: { if (shell.panel === "ethernet") selectPanel("ethernet"); }
    onBluetoothHeightChanged: { if (shell.panel === "bluetooth") selectPanel("bluetooth"); }
    readonly property int headerHeight: 40
    onWeatherHeightChanged: { if (shell.panel === "weather") selectPanel("weather"); }
    readonly property int overviewTop: 123
    readonly property int overviewInset: 21
    readonly property int popupHeight: overviewTop + overview.implicitHeight + 12
    readonly property int pillRadius: 20
    readonly property int sideInset: 20
    readonly property int clockGap: 14
    readonly property int compactClockWidth: Math.ceil(clockMetrics.width) + 2
    readonly property real compactContentWidth: compactClockWidth + clockGap + layoutLabel.width
    readonly property real clockCenter: Math.round((width - compactContentWidth) / 2) + compactClockWidth / 2
    readonly property real layoutLeft: clockCenter + compactClockWidth / 2 + clockGap
    readonly property int notificationGap: 12
    readonly property int notificationSlot: 30
    readonly property bool hasUnreadNotifications: shell.notifications.unread > 0
    readonly property int privacyGap: 8
    readonly property int privacyButtonWidth: 32
    readonly property int privacyButtonSpacing: 2
    readonly property int privacyCount: Number(shell.audio.micInUse) + Number(shell.screenSharing)
    readonly property int privacySpace: privacyCount > 0 ? privacyGap + privacyCount * privacyButtonWidth + (privacyCount - 1) * privacyButtonSpacing : 0
    readonly property int compactRightSpace: privacySpace + (hasUnreadNotifications ? notificationSlot : 0)
    readonly property real compactWidth: Math.ceil((compactContentWidth + 36 + compactRightSpace) / 2) * 2
    readonly property real popupWidth: Math.min(width - 24, 2 * overviewInset + Math.ceil(overview.implicitWidth / 2) * 2)
    readonly property real popupX: Math.round(Math.max(12, Math.min(width - popupWidth - 12, clockCenter - popupWidth / 2)))
    readonly property real targetWidth: Math.min(width - 24, shell.panel || hiddenPanelVisible ? paneWidth : popupOpen ? popupWidth : compactWidth + feedbackLeft + feedbackRight)
    readonly property real targetHeight: shell.panel || hiddenPanelVisible ? paneHeight : popupOpen ? popupHeight : headerHeight
    // Animate position and size together, including the return from a drag.
    // Standalone views use the reveal animation instead of the compact morph.
    // Snap all painted coordinates to whole pixels to avoid text shimmer.
    readonly property rect targetGeometry: Qt.rect(
        pinnedLauncher ? launcherPosition.x : popupOpen ? popupX
            : (width - targetWidth) / 2 + (hiddenPanelVisible ? 0 : (feedbackRight - feedbackLeft + (!expanded ? compactRightSpace : 0)) / 2),
        pinnedLauncher ? launcherPosition.y : theme.panelGap, targetWidth, targetHeight)
    property rect animatedGeometry: targetGeometry
    Behavior on animatedGeometry {
        enabled: !bar.dragPressed && !bar.idleHidden
        PropertyAnimation { duration: 220; easing.type: Easing.InOutCubic }
    }
    readonly property rect pillGeometry: Qt.rect(pill.x, pill.y, pill.width, pill.height)
    readonly property rect paneGeometry: Qt.rect(pill.x + panelLoader.x, pill.y + panelLoader.y, panelLoader.width, panelLoader.height)
    readonly property var activePane: panelLoader.item
    readonly property real detailsOpacity: Math.min(1, Math.max(0, (pill.height - headerHeight) / (popupHeight - headerHeight)))
    readonly property real overviewOpacity: detailsOpacity * header.opacity
    PillTheme { id: colors }
    TextMetrics { id: clockMetrics; font: colors.textFont; text: "00:00" }

    // This native surface never changes size or takes reserved app space.
    anchors { top: true; left: true; right: true }
    implicitHeight: screen ? screen.height : 1080
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "dotfiles-bar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: hidden || shell.captureActive ? WlrKeyboardFocus.None : shell.panel === "authentication" ? WlrKeyboardFocus.Exclusive : ["launcher", "portal", "credentials", "media", "mixer", "system", "power", "ethernet", "bluetooth", "calendar", "weather"].includes(shell.panel) ? WlrKeyboardFocus.OnDemand : shell.panel === "notifications" ? centerFocus.keyboardMode : WlrKeyboardFocus.None
    Region { id: pillInput; item: pill }
    // A fast pointer can reach the controls before the painted pill does.
    // Keep that destination interactive throughout hover expansion.
    Item {
        id: expansionTarget
        x: bar.popupX; y: bar.theme.panelGap
        width: bar.popupWidth; height: bar.popupHeight
    }
    Region { id: expansionInput; item: expansionTarget }
    Region { id: outsideInput; item: bar.contentItem }
    // Keep the native input region and focus grab intact until release. A fast
    // pointer can get ahead of the painted surface between rendering frames.
    mask: Region { regions: bar.hidden ? [] : bar.shell.panel && (!bar.pinnedLauncher || bar.dragPressed) ? [outsideInput] : bar.popupOpen ? [pillInput, expansionInput] : [pillInput] }
    ReplyFocus { id: centerFocus; available: bar.shell.panel === "notifications" && !bar.hidden && !bar.shell.captureActive; store: bar.shell.notifications; surface: "center"; targetWindow: bar }
    MouseArea {
        anchors.fill: parent
        enabled: bar.shell.panel.length > 0 && !bar.pinnedLauncher && !bar.dragPressed
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onPressed: bar.dismiss()
        onWheel: event => event.accepted = false
    }
    function dismiss() { endLauncherDrag(); shell.panel = ""; }
    function handleEscape() {
        if (shell.panel === "credentials" && shell.credentials.active) shell.credentials.finish({response: 1});
        else dismiss();
    }
    function openPanel(name) { trayMenu.visible = false; shell.toggle(name); }
    property var portalPane: null
    property var credentialPane: null
    property var authenticationPane: null
    function finishPanelClose() {
        if (!shell.panel && !hiddenPanelVisible && pill.height === targetHeight) {
            shownPanel = "";
            launcherDragged = false;
        }
    }
    function selectPanel(name) {
        // Retain this geometry until the closing fade has finished. The popup's
        // layout must not be resized to the compact pill while still visible.
        const portalWidth = portalPane?.desiredWidth || (shell.portal.data.kind === "share" ? 680 : shell.portal.data.kind === "access" ? 440 : 560);
        paneWidth = Math.min(width - 24, name === "authentication" ? (authenticationPane?.desiredWidth || 480) : name === "credentials" ? (credentialPane?.desiredWidth || 460) : ["ethernet", "bluetooth"].includes(name) ? 460 : name === "portal" ? portalWidth : ["launcher", "weather"].includes(name) ? 560 : name === "mixer" ? 520 : name === "calendar" ? 900 : 620);
        paneHeight = Math.min(height - 24, name === "authentication" ? (authenticationPane?.desiredHeight || 260) : name === "credentials" ? (credentialPane?.desiredHeight || 340) : name === "portal" ? (portalPane?.desiredHeight || 428) : name === "launcher" ? 428 : name === "mixer" ? 136 : name === "notifications" ? 816 : name === "calendar" ? calendarHeight : name === "bluetooth" ? bluetoothHeight : name === "ethernet" ? networkHeight : name === "media" ? mediaHeight : name === "system" ? systemHeight : name === "weather" ? weatherHeight : 220);
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
    Connections {
        target: bar.authenticationPane
        function onDesiredHeightChanged() { if (bar.shell.panel === "authentication") bar.selectPanel("authentication"); }
    }
    onWidthChanged: { if (shell.panel) selectPanel(shell.panel); }
    onHeightChanged: { if (shell.panel) selectPanel(shell.panel); }
    Shortcut { sequence: "Escape"; enabled: !!bar.shell.panel && !bar.shell.captureActive; context: Qt.WindowShortcut; onActivated: bar.handleEscape() }
    Connections {
        target: bar.shell
        function onCaptureActiveChanged() {
            focusLoss.stop();
            if (!bar.shell.captureActive && bar.shell.panel && !bar.hidden) {
                if (centerFocus.editing && centerFocus.grab) centerFocus.grab.active = true;
                if (bar.paneHasSearch && panelLoader.item) panelLoader.item.focusSearch();
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
                if (bar.paneHasSearch) { if (panelLoader.item) panelLoader.item.activate(); focusDelay.restart(); }
            } else {
                unload.restart();
                if (bar.launcherDragged) { bar.suppressHover = true; hoverRelease.restart(); }
                bar.hoverExpanded = !bar.suppressHover && bar.pillHovered;
                bar.finishPanelClose();
            }
        }
    }
    Connections {
        target: centerFocus.grab
        function onCleared() { if (centerFocus.editing) bar.lostFocus(); }
    }
    onHiddenChanged: {
        if (hidden) { trayMenu.visible = false; collapse.stop(); focusLoss.stop(); }
        else if (!shell.captureActive && paneHasSearch && panelLoader.item) panelLoader.item.focusSearch();
    }
    onFullscreenChanged: { if (fullscreen) hoverExpanded = false; }
    Timer { id: focusDelay; interval: 230; onTriggered: { if (!bar.shell.captureActive && bar.paneHasSearch && panelLoader.item) panelLoader.item.focusSearch(); } }
    Timer { id: collapse; interval: 240; onTriggered: { if (!bar.pillHovered && !bar.shell.panel && !trayMenu.visible && !bar.hidden) bar.hoverExpanded = false; } }
    TrayMenu { id: trayMenu; theme: colors; onVisibleChanged: { if (!visible && !bar.pillHovered) collapse.restart(); } }
    HoverHandler { id: hover; enabled: !bar.hidden }
    Item {
        id: pill
        objectName: "floatingPill"
        readonly property Item controlEmber: ember
        width: Math.round(bar.animatedGeometry.width / 2) * 2
        height: Math.round(bar.animatedGeometry.height)
        x: Math.round(bar.animatedGeometry.x)
        y: Math.round(bar.animatedGeometry.y)
        transform: Translate { y: bar.idleHidden ? Math.round(-12 * (1 - bar.hiddenPanelReveal)) : 0 }
        opacity: bar.shell.pillHidden ? 0 : bar.idleHidden ? bar.hiddenPanelReveal : 1
        onHeightChanged: bar.finishPanelClose()
        PillBackground {
            anchors.fill: parent
            theme: colors
            radius: bar.pillRadius + Math.round(11 * bar.overviewOpacity)
        }
        PillOverviewSurface {
            id: overviewSurface
            x: -shadowMargin; y: -shadowMargin
            width: bar.popupWidth + 2 * shadowMargin
            height: bar.popupHeight + 2 * shadowMargin
            theme: colors
            radius: 31.25
            opacity: bar.overviewOpacity
            visible: opacity > 0
            enabled: false
            // Scale the painted surface during the morph so its shadow only
            // needs repainting when the finished overview changes size.
            transform: Scale {
                origin.x: overviewSurface.shadowMargin
                origin.y: overviewSurface.shadowMargin
                xScale: pill.width / Math.max(1, bar.popupWidth)
                yScale: pill.height / Math.max(1, bar.popupHeight)
            }
        }
        Item {
            anchors.fill: parent
            clip: true
            MouseArea { anchors.fill: parent; onWheel: event => event.accepted = false }
            Item {
                id: header
                objectName: "pillHeader"
                width: parent.width; height: Math.min(pill.height, bar.popupHeight)
                visible: !bar.idleHidden
                opacity: bar.idleHidden || bar.shownPanel ? 0 : 1
                enabled: opacity > 0.95
                Behavior on opacity { enabled: !bar.idleHidden; NumberAnimation { duration: 100 } }

                Item {
                    id: timeButton
                    // Enlarge around the compact clock's horizontal center.
                    readonly property real expandedWidth: Math.min(264, bar.popupWidth - 2 * bar.overviewInset)
                    width: Math.round(bar.compactClockWidth + (expandedWidth - bar.compactClockWidth) * bar.detailsOpacity)
                    height: Math.round(bar.headerHeight + (bar.overviewTop - 7 - bar.headerHeight) * bar.detailsOpacity)
                    x: Math.round(bar.clockCenter - width / 2) - pill.x
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Calendar"
                    Accessible.onPressAction: bar.openPanel("calendar")
                    Keys.onReturnPressed: bar.openPanel("calendar")
                    Keys.onSpacePressed: bar.openPanel("calendar")
                    Text {
                        id: clockLabel
                        x: Math.round((parent.width - width) / 2)
                        y: Math.round((bar.headerHeight - height) / 2 + 28 * bar.detailsOpacity)
                        text: Qt.formatDateTime(bar.shell.clock.date, "hh:mm")
                        font.family: colors.fontFamily
                        font.features: colors.textFont.features
                        font.weight: bar.detailsOpacity > 0 ? Font.Medium : colors.fontWeight
                        font.letterSpacing: -2.5 * bar.detailsOpacity
                        font.pixelSize: Math.round(colors.bodySize + (55 - colors.bodySize) * bar.detailsOpacity)
                        color: Qt.tint(colors.text, Qt.alpha(colors.overviewInk, bar.detailsOpacity))
                    }
                    Text {
                        width: parent.width
                        y: clockLabel.y + clockLabel.height + 1
                        text: Qt.formatDateTime(bar.shell.clock.date, "dddd, MMMM d")
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.family: colors.fontFamily
                        font.pixelSize: 16
                        color: colors.overviewSecondary
                        opacity: bar.detailsOpacity
                        visible: opacity > 0
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bar.openPanel("calendar") }
                }
                Text {
                    id: layoutLabel
                    width: Math.ceil(implicitWidth)
                    x: bar.layoutLeft - pill.x
                    y: Math.round((bar.headerHeight - height) / 2)
                    text: bar.shell.layoutLabel
                    font: colors.textFont
                    color: colors.secondary
                    opacity: 1 - bar.detailsOpacity
                    visible: opacity > 0
                }
                ShellButton {
                    objectName: "pillNotificationIndicator"
                    readonly property int expandedSize: 45
                    readonly property bool highlighted: hovered || (bar.shell.emberEnabled && bar.emberTarget === emberSlot)
                    readonly property color fill: highlighted ? colors.overviewButtonHover : colors.overviewButton
                    readonly property real compactX: layoutLabel.x + layoutLabel.width + bar.notificationGap
                    readonly property real expandedX: bar.popupX + bar.popupWidth - bar.overviewInset - expandedSize - pill.x
                    x: Math.round(compactX + (expandedX - compactX) * bar.detailsOpacity)
                    y: Math.round(4 + 17 * bar.detailsOpacity)
                    width: Math.round(18 + (expandedSize - 18) * bar.detailsOpacity)
                    height: Math.round(32 + (expandedSize - 32) * bar.detailsOpacity)
                    radius: height / 2
                    color: Qt.alpha(fill, fill.a * bar.detailsOpacity)
                    opacity: bar.hasUnreadNotifications ? 1 : bar.detailsOpacity
                    visible: opacity > 0
                    enabled: bar.hasUnreadNotifications || (bar.popupOpen && opacity > 0.95)
                    theme: colors
                    hint: "Notifications"; onClicked: bar.openPanel("notifications")
                    ShellIcon {
                        name: "bell"
                        tint: colors.overviewInk
                        width: 21; height: 21
                        anchors.centerIn: parent
                        opacity: bar.detailsOpacity
                        visible: opacity > 0
                    }
                    Rectangle {
                        width: Math.round(12 - 5 * bar.detailsOpacity); height: width; radius: width / 2
                        x: Math.round((parent.width - width) / 2 + 12 * bar.detailsOpacity)
                        y: Math.round((parent.height - height) / 2 - 10 * bar.detailsOpacity)
                        color: Qt.tint(colors.focusColor, Qt.alpha(colors.overviewAccent, bar.detailsOpacity))
                        visible: bar.hasUnreadNotifications
                    }
                }
                Row {
                    x: layoutLabel.x + layoutLabel.width + (bar.hasUnreadNotifications ? bar.notificationSlot : 0) + bar.privacyGap
                    y: 4; spacing: bar.privacyButtonSpacing
                    opacity: 1 - bar.detailsOpacity
                    visible: opacity > 0
                    enabled: opacity > 0.5
                    ShellButton {
                        objectName: "pillMicrophoneIndicator"
                        visible: bar.shell.audio.micInUse
                        theme: colors; width: bar.privacyButtonWidth; height: 32
                        icon: bar.shell.audio.activeMicsMuted ? "mic-off" : "mic"
                        hint: bar.shell.audio.activeMicsMuted ? "Unmute microphone" : "Mute microphone"
                        onClicked: bar.shell.audio.toggleActiveMics()
                    }
                    ShellButton {
                        objectName: "pillScreenSharingIndicator"
                        visible: bar.shell.screenSharing
                        theme: colors; width: bar.privacyButtonWidth; height: 32
                        icon: "screen-share"; hint: "Stop screen sharing"
                        onClicked: bar.shell.stopScreenSharing()
                    }
                }
                PillOverview {
                    id: overview
                    x: bar.popupX + bar.overviewInset - pill.x; y: bar.overviewTop
                    width: Math.max(0, bar.popupWidth - 2 * bar.overviewInset)
                    height: implicitHeight
                    shell: bar.shell; theme: colors; spaces: bar.spaces
                    opacity: bar.detailsOpacity
                    enabled: bar.popupOpen && opacity > 0.95
                    onPanelRequested: name => bar.openPanel(name)
                    onTrayMenuRequested: (trayItem, trayAnchor) => {
                        const point = trayAnchor.mapToItem(bar.contentItem, 0, trayAnchor.height);
                        trayMenu.open(trayItem, bar, point.x, point.y, trayAnchor.width);
                    }
                }
            }
            Item {
                id: panelLoader
                readonly property int inset: ["launcher", "portal", "credentials", "authentication"].includes(bar.shownPanel) ? 12 : 24
                x: bar.launcherDragged ? inset : Math.round((bar.width - bar.paneWidth) / 2) - pill.x + inset
                y: ["launcher", "portal", "credentials", "authentication"].includes(bar.shownPanel) ? 8 : 16
                width: bar.paneWidth - inset * 2
                height: bar.paneHeight - y - (["notifications", "calendar"].includes(bar.shownPanel) ? y : inset)
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
                        onLoaded: { if (modelData === "portal") bar.portalPane = item; if (modelData === "credentials") bar.credentialPane = item; if (modelData === "authentication") bar.authenticationPane = item; if (modelData === bar.shell.panel && bar.paneHasSearch) { item.activate(); if (["portal", "credentials", "authentication"].includes(modelData)) Qt.callLater(() => bar.selectPanel(modelData)); } }
                    }
                }
            }

        }
        Keys.onEscapePressed: bar.handleEscape()
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
        x: Math.round((bar.width + bar.compactWidth + bar.compactRightSpace) / 2) - pill.x - 4; y: 0
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
    Component { id: authenticationComponent; AuthenticationPane { shell: bar.shell; theme: colors } }
    Component { id: credentialComponent; CredentialPane { shell: bar.shell; theme: colors } }
    Component { id: portalComponent; PortalPane { shell: bar.shell; theme: colors } }
    Component { id: notificationsComponent; NotificationCenter { shell: bar.shell; theme: colors } }
    Component {
        id: calendarComponent
        CalendarPane {
            shell: bar.shell; theme: colors
            onImplicitHeightChanged: bar.calendarHeight = implicitHeight + 32
            Component.onCompleted: bar.calendarHeight = implicitHeight + 32
        }
    }
    Component {
        id: bluetoothComponent
        BluetoothMenu {
            shell: bar.shell; theme: colors
            onImplicitHeightChanged: bar.bluetoothHeight = implicitHeight + 40
            Component.onCompleted: bar.bluetoothHeight = implicitHeight + 40
        }
    }
    Component {
        id: networkComponent
        EthernetMenu {
            shell: bar.shell; theme: colors
            onImplicitHeightChanged: bar.networkHeight = implicitHeight + 40
            Component.onCompleted: bar.networkHeight = implicitHeight + 40
        }
    }
    Component {
        id: weatherComponent
        WeatherPane {
            shell: bar.shell; theme: colors
            onImplicitHeightChanged: bar.weatherHeight = Math.max(164, implicitHeight + 40)
            Component.onCompleted: bar.weatherHeight = Math.max(164, implicitHeight + 40)
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
        if (ember.interactionTarget) return ember.interactionTarget;
        if (shell.panel) return panelLoader.item?.emberTarget || null;
        return overview.workspaceSlot;
    }
    property alias ember: ember
    Ember {
        id: ember
        color: Qt.tint(colors.focusColor, Qt.alpha(colors.overviewAccent, bar.detailsOpacity * header.opacity))
        parent: pill
        anchors.fill: parent
        clip: true
        z: 10
        pointerHoldArea: bar.popupOpen && bar.pillHovered
            && bar.pointerPosition.y < pill.y + overview.y + overview.actionsHeight ? header : null
        target: bar.emberTarget
        active: bar.shell.emberEnabled && !!target && !bar.hidden
    }
}
