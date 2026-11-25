import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: bar
    required property var shell
    required property var theme
    readonly property alias pillTheme: colors
    readonly property var monitorInfo: shell.fixture ? null : Hyprland.monitorFor(screen)
    readonly property var activeWorkspace: monitorInfo?.activeWorkspace
    readonly property bool fullscreen: shell.fixture ? !!shell.fixtureData.fullscreen : !!activeWorkspace?.hasFullscreen
    readonly property bool workspaceEmpty: shell.fixture ? shell.fixtureData.workspaceEmpty === true
        : occupancy.emptyOutputs.includes(screen?.name)
    WorkspaceOccupancy { id: occupancy; enabled: !bar.shell.fixture && !!bar.screen }
    readonly property bool idleHidden: shell.pillSuppressed || (fullscreen && !shell.superHeld)
    readonly property bool pillConcealed: idleHidden || shell.pillHidden
    // Value feedback can briefly reveal the pill even while its idle state is hidden.
    readonly property bool hidden: !feedbackReveal && (shell.pillHidden || (!shell.panel && idleHidden))
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
    readonly property bool desktopOverviewAvailable: workspaceEmpty && !pillConcealed
    readonly property bool desktopExpanded: desktopOverviewAvailable && !shell.panel
    readonly property bool expanded: desktopExpanded || (!pillConcealed && (hoverExpanded || trayMenu.visible))
        || shell.panel.length > 0
    readonly property bool popupOpen: expanded && !shell.panel && !hiddenPanelVisible
    readonly property point pointerPosition: hover.point.position
    // Music shapes the idle pill unless notifications are muted.
    readonly property bool musicEffect: pillState === "compact" && !shell.notifications.dnd
        && shell.media.playingPlayers.length > 0
    readonly property string pillState: hidden ? "hidden" : shell.panel || (popupOpen ? "expanded"
        : valueFeedbackVisible || workspaceFeedbackVisible ? "osd" : "compact")
    // Track the pointer on the fixed native surface, not the animated header.
    readonly property bool pillHovered: hover.hovered && (
        (hover.point.position.x >= pill.x && hover.point.position.x < pill.x + pill.width
            && hover.point.position.y >= pill.y && hover.point.position.y < pill.y + headerHeight)
        || (popupOpen && hover.point.position.x >= expansionTarget.x
            && hover.point.position.x < expansionTarget.x + expansionTarget.width
            && hover.point.position.y >= expansionTarget.y && hover.point.position.y < expansionTarget.y + expansionTarget.height))
    // Workspace feedback can give way to the full overview. A value OSD or
    // temporary suppression can end while the pointer is still on the pill.
    readonly property bool canExpandOnHover: !workspaceEmpty && pillHovered && !hidden && !shell.panel && !valueFeedbackVisible && !suppressHover
    onPillHoveredChanged: {
        if (pillHovered) collapse.stop();
        else collapse.restart();
    }
    property bool hoverExpanded: false
    property bool suppressHover: false
    property string shownPanel: ""
    property bool panelCentered: false
    readonly property var paneNames: ["launcher", "portal", "credentials", "authentication", "notifications", "calendar", "bluetooth", "ethernet", "power", "media", "mixer", "system", "weather"]
    readonly property bool paneHasSearch: ["launcher", "portal", "credentials", "authentication", "weather"].includes(shell.panel)
    property var retained: ({})
    readonly property bool workspaceFeedbackVisible: !expanded && !hiddenPanelVisible && !pillConcealed
        && shell.osd.visible && shell.osd.kind === "workspace"
    readonly property bool valueFeedbackVisible: !panelVisible && shell.osd.visible && shell.osd.kind !== "workspace"
    readonly property bool feedbackReveal: valueFeedbackVisible && pillConcealed
    readonly property real feedbackLeft: workspaceFeedbackVisible ? workspaceWing.naturalWidth + 14 : 0
    readonly property int valueFeedbackGap: 14
    readonly property real feedbackRight: valueFeedbackVisible && !feedbackReveal ? valueWing.naturalWidth + valueFeedbackGap : 0
    onPillConcealedChanged: { if (pillConcealed) trayMenu.visible = false; }
    onWorkspaceEmptyChanged: {
        trayMenu.visible = false;
        if (workspaceEmpty) hoverExpanded = false;
    }
    onPopupOpenChanged: { if (popupOpen) warm.restart(); }
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
    property real calendarHeight: 1348
    readonly property int calendarInset: 21
    property real mediaHeight: 240
    property real systemHeight: 480
    property real weatherHeight: 220
    property real networkHeight: 270
    property real bluetoothHeight: 340
    property real bluetoothTop: theme.panelGap
    property real powerHeight: colors.overviewControlSize + 2 * overviewInset
    property real mixerHeight: 2 * (colors.overviewControlSize + 2 * colors.overviewControlPadding + overviewInset) + colors.overviewGap
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
    function suppressHoverBriefly() {
        suppressHover = true;
        hoverRelease.restart();
        hoverExpanded = false;
    }
    function lostFocus() {
        // Polkit owns exclusive keyboard focus; its handoff must not dismiss it.
        if (shell.panel === "authentication") return;
        if (shell.panel && !pinnedLauncher && !dragPressed && !hidden && !shell.captureActive) {
            suppressHoverBriefly();
            dismiss();
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
    onMixerHeightChanged: { if (shell.panel === "mixer") selectPanel("mixer"); }
    onPowerHeightChanged: { if (shell.panel === "power") selectPanel("power"); }
    readonly property int headerHeight: 40
    onWeatherHeightChanged: { if (shell.panel === "weather") selectPanel("weather"); }
    readonly property int overviewTop: 123
    readonly property int overviewInset: colors.overviewInset
    readonly property real overviewRadius: colors.overviewRadius
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
    readonly property bool notificationsMuted: shell.notifications.dnd
    readonly property bool showNotificationIndicator: notificationsMuted || hasUnreadNotifications
    readonly property int notificationSpace: showNotificationIndicator ? notificationSlot : 0
    readonly property int privacyGap: 8
    readonly property int privacyButtonWidth: 32
    readonly property int privacyButtonSpacing: 2
    readonly property int privacyCount: Number(shell.audio.micInUse) + Number(shell.screenSharing)
    readonly property int privacySpace: privacyCount > 0 ? privacyGap + privacyCount * privacyButtonWidth + (privacyCount - 1) * privacyButtonSpacing : 0
    readonly property int compactRightSpace: privacySpace + notificationSpace
    readonly property real compactWidth: Math.ceil((compactContentWidth + 36 + compactRightSpace) / 2) * 2
    readonly property real valueFeedbackWidth: 2 * sideInset + notificationSpace + valueWing.naturalWidth
    readonly property real popupWidth: Math.min(width - 24, 2 * overviewInset + Math.ceil(overview.implicitWidth / 2) * 2)
    readonly property real popupX: desktopExpanded ? Math.round((width - popupWidth) / 2)
        : Math.round(Math.max(12, Math.min(width - popupWidth - 12, clockCenter - popupWidth / 2)))
    function centeredY(itemHeight) { return Math.max(theme.panelGap, Math.round((height - itemHeight) / 2)); }
    readonly property real popupY: desktopExpanded ? centeredY(popupHeight) : theme.panelGap
    readonly property real bluetoothY: Math.min(bluetoothTop, Math.floor(height / 2))
    readonly property bool panelVisible: !!shell.panel || hiddenPanelVisible
    readonly property real targetWidth: Math.min(width - 24, panelVisible ? paneWidth : popupOpen ? popupWidth
        : feedbackReveal ? valueFeedbackWidth : compactWidth + feedbackLeft + feedbackRight)
    readonly property real targetHeight: panelVisible ? paneHeight : popupOpen ? popupHeight : headerHeight
    readonly property real targetY: {
        if (pinnedLauncher) return launcherPosition.y;
        if (panelVisible && panelCentered) return shownPanel === "bluetooth" ? bluetoothY : centeredY(targetHeight);
        return popupOpen ? popupY : theme.panelGap;
    }
    // Animate position and size together, including the return from a drag.
    // Standalone views use the reveal animation instead of the compact morph.
    // Snap all painted coordinates to whole pixels to avoid text shimmer.
    readonly property rect targetGeometry: Qt.rect(
        pinnedLauncher ? launcherPosition.x : popupOpen ? popupX
            : (width - targetWidth) / 2 + (!expanded && !hiddenPanelVisible && !feedbackReveal
                ? (compactRightSpace + feedbackRight - feedbackLeft) / 2 : 0),
        targetY, targetWidth, targetHeight)
    property rect animatedGeometry: targetGeometry
    Behavior on animatedGeometry {
        enabled: !bar.dragPressed && !bar.idleHidden
        PropertyAnimation { id: pillResize; duration: 220; easing.type: Easing.InOutCubic }
    }
    readonly property rect pillGeometry: Qt.rect(pill.x, pill.y, pill.width, pill.height)
    readonly property rect paneGeometry: Qt.rect(pill.x + panelLoader.x, pill.y + panelLoader.y, panelLoader.width, panelLoader.height)
    readonly property var activePane: panelLoader.item
    readonly property real detailsOpacity: feedbackReveal ? 0 : Math.min(1, Math.max(0, (pill.height - headerHeight) / (popupHeight - headerHeight)))
    readonly property real overviewControlLeft: popupX + overviewInset - pill.x
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
        x: bar.popupX; y: bar.popupY
        width: bar.popupWidth; height: bar.popupHeight
    }
    Region { id: expansionInput; item: expansionTarget }
    Region { id: outsideInput; item: bar.contentItem }
    // Keep the native input region and focus grab intact until release. A fast
    // pointer can get ahead of the painted surface between rendering frames.
    mask: Region { regions: bar.hidden || bar.shell.pillHidden ? [] : bar.shell.panel && (!bar.pinnedLauncher || bar.dragPressed) ? [outsideInput] : bar.popupOpen ? [pillInput, expansionInput] : [pillInput] }
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
        if (shell.panel === "mixer" && activePane?.closeDevicePicker?.()) return;
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
        const maxHeight = name === "bluetooth" && panelCentered ? height - bluetoothY - 12 : height - 24;
        paneWidth = Math.min(width - 24, name === "authentication" ? (authenticationPane?.desiredWidth || 480) : name === "credentials" ? (credentialPane?.desiredWidth || 460) : ["ethernet", "bluetooth"].includes(name) ? 460 : name === "portal" ? portalWidth : name === "launcher" ? 560 : name === "weather" ? 584 : name === "mixer" ? 540 : name === "calendar" ? 1256 : name === "power" ? 480 : 620);
        paneHeight = Math.min(maxHeight, name === "authentication" ? (authenticationPane?.desiredHeight || 260) : name === "credentials" ? (credentialPane?.desiredHeight || 340) : name === "portal" ? (portalPane?.desiredHeight || 428) : name === "launcher" ? 428 : name === "mixer" ? mixerHeight : name === "notifications" ? 816 : name === "calendar" ? calendarHeight : name === "bluetooth" ? bluetoothHeight : name === "ethernet" ? networkHeight : name === "media" ? mediaHeight : name === "system" ? systemHeight : name === "weather" ? weatherHeight : name === "power" ? powerHeight : 220);
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
                // Keep the origin through resizes and switches between panels.
                if (!bar.shownPanel) bar.panelCentered = bar.desktopOverviewAvailable;
                if (bar.shell.panel === "bluetooth" && bar.panelCentered && bar.shownPanel !== "bluetooth")
                    bar.bluetoothTop = bar.centeredY(bar.popupHeight);
                bar.selectPanel(bar.shell.panel);
                trayMenu.visible = false;
                if (bar.paneHasSearch) { if (panelLoader.item) panelLoader.item.activate(); focusDelay.restart(); }
            } else {
                unload.restart();
                if (bar.launcherDragged) bar.suppressHoverBriefly();
                else bar.hoverExpanded = !bar.workspaceEmpty && !bar.idleHidden && !bar.shell.pillHidden && !bar.suppressHover && bar.pillHovered;
                bar.finishPanelClose();
            }
        }
    }
    Connections {
        target: centerFocus.grab
        function onCleared() { if (centerFocus.editing) bar.lostFocus(); }
    }
    onHiddenChanged: {
        if (hidden) {
            trayMenu.visible = false; collapse.stop(); focusLoss.stop();
            if (idleHidden) hoverExpanded = false;
        }
        else if (!shell.captureActive && paneHasSearch && panelLoader.item) panelLoader.item.focusSearch();
    }
    onFullscreenChanged: { if (fullscreen) hoverExpanded = false; }
    Timer { id: focusDelay; interval: 230; onTriggered: { if (!bar.shell.captureActive && bar.paneHasSearch && panelLoader.item) panelLoader.item.focusSearch(); } }
    Timer {
        interval: 140
        running: bar.canExpandOnHover && !bar.popupOpen
        onTriggered: { if (bar.canExpandOnHover && !bar.popupOpen) bar.hoverExpanded = true; }
    }
    Timer { id: collapse; interval: 240; onTriggered: { if (!bar.pillHovered && !bar.shell.panel && !trayMenu.visible && !bar.hidden) bar.hoverExpanded = false; } }
    TrayMenu { id: trayMenu; theme: colors; onVisibleChanged: { if (!visible && !bar.pillHovered) collapse.restart(); } }
    HoverHandler { id: hover; enabled: !bar.hidden }
    Item {
        id: pill
        objectName: "floatingPill"
        readonly property Item controlEmber: ember
        readonly property string gradientKey: bar.shownPanel === "portal" ? bar.shell.portal.data.kind || "apps" : bar.shownPanel
        readonly property var panelGradient: colors.popupGradients[gradientKey] || null
        readonly property real frameRadius: ["portal", "notifications", "credentials", "authentication"].includes(bar.shownPanel)
            ? bar.pillRadius : bar.overviewRadius
        width: Math.round(bar.animatedGeometry.width / 2) * 2
        height: Math.round(bar.animatedGeometry.height)
        x: Math.round(bar.animatedGeometry.x)
        y: Math.round(bar.animatedGeometry.y)
        transform: Translate { y: bar.idleHidden && !bar.feedbackReveal ? Math.round(-12 * (1 - bar.hiddenPanelReveal)) : 0 }
        opacity: bar.feedbackReveal ? 1 : bar.shell.pillHidden ? 0 : bar.idleHidden ? bar.hiddenPanelReveal : 1
        onHeightChanged: bar.finishPanelClose()
        PillBackdrop {
            anchors.fill: parent
            theme: colors
            compactHeight: bar.headerHeight
            compactRadius: bar.pillRadius
            frameRadius: pill.frameRadius
            panelGradient: pill.panelGradient
            overviewBlend: bar.overviewOpacity
            resizing: pillResize.running
            targetArea: bar.targetWidth * bar.targetHeight
        }
        PillLiquid {
            theme: colors
            levels: bar.shell.musicLevels
            pillWidth: pill.width
            pillHeight: pill.height
            active: bar.musicEffect
        }
        ClippingRectangle {
            anchors.fill: parent
            color: "transparent"
            radius: panelLoader.scrollsToBottom ? pill.frameRadius : 0
            clip: true
            MouseArea { anchors.fill: parent; onWheel: event => event.accepted = false }
            Item {
                id: header
                objectName: "pillHeader"
                readonly property EmberHoverGroup emberHoverGroup: EmberHoverGroup {
                    parent: header
                    enabled: bar.popupOpen && !bar.hidden
                    holdHeight: overview.y + overview.actionsHeight
                }
                width: parent.width; height: Math.min(pill.height, bar.popupHeight)
                visible: !bar.idleHidden || bar.feedbackReveal
                opacity: !visible || bar.shownPanel ? 0 : 1
                enabled: opacity > 0.95
                Behavior on opacity { enabled: !bar.idleHidden; NumberAnimation { duration: 100 } }

                Item {
                    id: timeButton
                    visible: !bar.feedbackReveal
                    readonly property real expandedWidth: Math.min(264, bar.popupWidth - 2 * bar.overviewInset)
                    readonly property real expandedCenter: bar.popupX + bar.popupWidth / 2
                    width: Math.round(bar.compactClockWidth + (expandedWidth - bar.compactClockWidth) * bar.detailsOpacity)
                    height: Math.round(bar.headerHeight + (bar.overviewTop - 7 - bar.headerHeight) * bar.detailsOpacity)
                    x: Math.round(bar.clockCenter + (expandedCenter - bar.clockCenter) * bar.detailsOpacity - width / 2) - pill.x
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
                        font: colors.textFont
                        color: colors.overviewSecondary
                        opacity: bar.detailsOpacity
                        visible: opacity > 0
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: bar.openPanel("calendar") }
                }
                Text {
                    id: layoutLabel
                    readonly property real compactX: bar.layoutLeft - pill.x
                    readonly property real feedbackProgress: bar.valueFeedbackVisible ? bar.detailsOpacity : 0
                    width: Math.ceil(implicitWidth)
                    x: Math.round(compactX + (bar.overviewControlLeft - compactX) * feedbackProgress)
                    y: Math.round((bar.headerHeight - height) / 2 + 24 * feedbackProgress)
                    text: bar.shell.layoutLabel
                    font: colors.textFont
                    color: colors.secondary
                    opacity: bar.valueFeedbackVisible ? 1 : 1 - bar.detailsOpacity
                    visible: !bar.feedbackReveal && opacity > 0
                }
                ShellButton {
                    objectName: "pillNotificationIndicator"
                    readonly property int expandedSize: 45
                    readonly property bool highlighted: hovered || (bar.shell.emberEnabled && bar.emberTarget === emberSlot)
                    readonly property color fill: highlighted ? colors.overviewButtonHover : colors.overviewButton
                    readonly property real compactX: bar.feedbackReveal ? bar.sideInset : layoutLabel.compactX + layoutLabel.width + bar.notificationGap
                    readonly property real expandedX: bar.popupX + bar.popupWidth - bar.overviewInset - expandedSize - pill.x
                    x: Math.round(compactX + (expandedX - compactX) * bar.detailsOpacity)
                    y: Math.round(4 + 17 * bar.detailsOpacity)
                    width: Math.round(18 + (expandedSize - 18) * bar.detailsOpacity)
                    height: Math.round(32 + (expandedSize - 32) * bar.detailsOpacity)
                    radius: height / 2
                    color: Qt.alpha(fill, fill.a * bar.detailsOpacity)
                    opacity: bar.showNotificationIndicator ? 1 : bar.detailsOpacity
                    visible: opacity > 0
                    enabled: bar.showNotificationIndicator || (bar.popupOpen && opacity > 0.95)
                    theme: colors
                    hint: bar.notificationsMuted ? "Notifications muted" : "Notifications"
                    onClicked: bar.openPanel("notifications")
                    ShellIcon {
                        name: "bell-off"
                        tint: colors.overviewAccent
                        anchors.centerIn: parent
                        opacity: bar.notificationsMuted ? 1 - bar.detailsOpacity : 0
                        visible: opacity > 0
                    }
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
                        opacity: bar.notificationsMuted ? bar.detailsOpacity : 1
                        visible: bar.hasUnreadNotifications && opacity > 0
                    }
                }
                Row {
                    x: layoutLabel.compactX + layoutLabel.width + bar.notificationSpace + bar.privacyGap
                    y: 4; spacing: bar.privacyButtonSpacing
                    opacity: 1 - bar.detailsOpacity
                    visible: !bar.feedbackReveal && opacity > 0
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
                    x: bar.overviewControlLeft; y: bar.overviewTop
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
                readonly property real inset: ["mixer", "power"].includes(bar.shownPanel) ? bar.overviewInset
                    : bar.shownPanel === "calendar" ? bar.calendarInset
                    : ["launcher", "portal", "credentials", "authentication"].includes(bar.shownPanel) ? 12 : 24
                readonly property real bottomInset: ["notifications", "calendar"].includes(bar.shownPanel) ? y : inset
                // Give these scroll views the full height. Their own margins
                // add the inset at the end of the scroll range.
                readonly property bool scrollsToBottom: ["launcher", "notifications", "calendar", "bluetooth", "weather", "media", "mixer"].includes(bar.shownPanel)
                x: bar.launcherDragged ? inset : Math.round((bar.width - bar.paneWidth) / 2) - pill.x + inset
                y: ["mixer", "calendar", "power"].includes(bar.shownPanel) ? inset : ["launcher", "portal", "credentials", "authentication"].includes(bar.shownPanel) ? 8 : 16
                width: bar.paneWidth - inset * 2
                height: bar.paneHeight - y - (scrollsToBottom ? 0 : bottomInset)
                readonly property var item: bar.shownPanel ? paneSlots.itemAt(bar.paneNames.indexOf(bar.shownPanel))?.item || null : null
                Repeater {
                    id: paneSlots
                    model: bar.paneNames
                    Loader {
                        required property string modelData
                        anchors.fill: parent
                        active: !!bar.retained[modelData]
                        asynchronous: modelData === "calendar"
                        opacity: modelData === bar.shownPanel && (bar.shell.panel || bar.hiddenPanelVisible)
                            && pill.height > bar.headerHeight + 30 && (!asynchronous || status === Loader.Ready) ? 1 : 0
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
        showing: bar.workspaceFeedbackVisible
        visible: !bar.feedbackReveal && reveal > 0
        x: bar.sideInset; y: 0
    }
    PillWing {
        id: valueWing; objectName: "valueWing"
        readonly property real compactX: bar.feedbackReveal ? bar.sideInset + bar.notificationSpace
            : layoutLabel.compactX + layoutLabel.width + bar.compactRightSpace + bar.valueFeedbackGap
        parent: header
        shell: bar.shell; theme: colors; spaces: bar.spaces
        showing: bar.valueFeedbackVisible
        visible: showing && reveal > 0
        x: Math.round(compactX + (bar.overviewControlLeft - compactX) * bar.detailsOpacity)
        y: Math.round(48 * bar.detailsOpacity)
    }
    Component {
        id: launcherComponent
        LauncherPane {
            shell: bar.shell; theme: colors
            scrollBottomPadding: panelLoader.bottomInset
            onDragStarted: (x, y) => bar.beginLauncherDrag(x, y)
            onDragMoved: (x, y) => bar.moveLauncherDrag(x, y)
            onDragFinished: bar.endLauncherDrag()
        }
    }
    Component { id: authenticationComponent; AuthenticationPane { shell: bar.shell; theme: colors } }
    Component { id: credentialComponent; CredentialPane { shell: bar.shell; theme: colors } }
    Component { id: portalComponent; PortalPane { shell: bar.shell; theme: colors } }
    Component {
        id: notificationsComponent
        NotificationCenter { shell: bar.shell; theme: colors; scrollBottomPadding: panelLoader.bottomInset }
    }
    Component {
        id: calendarComponent
        CalendarPane {
            shell: bar.shell; theme: colors
            heightBudget: bar.height - 24 - 2 * bar.calendarInset
            bottomMargin: panelLoader.bottomInset
            onImplicitHeightChanged: bar.calendarHeight = implicitHeight + 2 * bar.calendarInset
            Component.onCompleted: bar.calendarHeight = implicitHeight + 2 * bar.calendarInset
        }
    }
    Component {
        id: bluetoothComponent
        BluetoothMenu {
            shell: bar.shell; theme: colors
            scrollBottomPadding: panelLoader.bottomInset
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
            bottomMargin: panelLoader.bottomInset
            onImplicitHeightChanged: bar.weatherHeight = Math.max(164, implicitHeight + 40)
            Component.onCompleted: bar.weatherHeight = Math.max(164, implicitHeight + 40)
        }
    }
    Component {
        id: powerComponent
        PowerPane {
            shell: bar.shell; theme: colors
            onImplicitHeightChanged: bar.powerHeight = implicitHeight + 2 * bar.overviewInset
            Component.onCompleted: bar.powerHeight = implicitHeight + 2 * bar.overviewInset
        }
    }
    Component {
        id: mediaComponent
        MediaPane {
            shell: bar.shell; theme: colors
            bottomMargin: panelLoader.bottomInset
            onImplicitHeightChanged: bar.mediaHeight = implicitHeight + 40
            Component.onCompleted: bar.mediaHeight = implicitHeight + 40
        }
    }
    Component {
        id: mixerComponent
        MixerPane {
            shell: bar.shell; theme: colors
            bottomMargin: panelLoader.bottomInset
            onImplicitHeightChanged: bar.mixerHeight = implicitHeight + 2 * bar.overviewInset
            Component.onCompleted: bar.mixerHeight = implicitHeight + 2 * bar.overviewInset
        }
    }
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
        if (workspaceFeedbackVisible) return workspaceWing.workspaceIndicator.emberSlot;
        if (!expanded) return null;
        if (ember.interactionTarget) return ember.interactionTarget;
        if (shell.panel) return panelLoader.item?.emberTarget || null;
        return overview.workspaceSlot;
    }
    property alias ember: ember
    Ember {
        id: ember
        color: ["mixer", "calendar"].includes(bar.shell.panel) ? colors.overviewAccent
            : Qt.tint(colors.focusColor, Qt.alpha(colors.overviewAccent, bar.detailsOpacity * header.opacity))
        parent: pill
        anchors.fill: parent
        clip: true
        z: 10
        target: bar.emberTarget
        active: bar.shell.emberEnabled && !!target && !bar.hidden
    }
}
