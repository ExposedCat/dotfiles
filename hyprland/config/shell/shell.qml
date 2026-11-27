//@ pragma IconTheme MacTahoe-blue
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
    id: root
    readonly property bool fixture: !!Quickshell.env("DOTFILES_SHELL_FIXTURE")
    property var fixtureData: ({})
    property string panel: ""
    property bool superHeld: false
    readonly property bool pillHidden: superHeld && !bar.fullscreen
    readonly property bool bannersHidden: superHeld !== bar.fullscreen
    property bool pillSuppressed: false
    property real gestureTimestamp: -1
    property string lastGesture: ""
    property real panelOriginX: 0
    property real panelOriginWidth: 56
    property alias bluetooth: bluetoothController
    property alias vpn: vpnController
    property var panelScreen: null
    property alias layout: keyboardLayoutController.layout
    property alias keyboard: keyboardLayoutController.keyboard
    property alias keyboardLayout: keyboardLayoutController
    readonly property bool screenSharing: sharing.active
    function stopScreenSharing() { sharing.stop(); }
    property bool captureActive: false
    property var captureClient: null
    property string actionError: ""
    property alias audio: sound
    property alias osd: osd
    property alias notifications: notifications
    property alias clock: clock
    property alias agenda: agenda
    property alias weather: weather
    property alias pill: bar
    property alias overlays: overlays
    property alias applications: appIndex
    property alias media: players
    property alias musicLevels: music
    property alias brightness: monitorBrightness
    property alias stats: systemStats
    property alias appearance: systemAppearance
    property alias portal: portalController
    property alias authentication: authenticationController
    property alias credentials: credentialController
    property bool emberEnabled: true
    readonly property var emberTarget: bar.emberTarget
    // HP OMEN is the main display. Fall back gracefully if it is disconnected.
    readonly property string mainOutput: fixture ? (fixtureData.mainOutput || "X11-1") : "DP-3"
    readonly property var mainScreen: Quickshell.screens.find(s => s.name === mainOutput) || Quickshell.screens[0]
    readonly property real desktopTop: Math.min(...Quickshell.screens.map(s => s.y))
    readonly property real desktopBottom: Math.max(...Quickshell.screens.map(s => s.y + s.height))
    readonly property string helper: Quickshell.env("DOTFILES_DESKTOP_BINARY") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hypr/bin/dotfiles-desktop"
    readonly property string backend: helper
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === (fixture ? fixtureData.focusedOutput : Hyprland.focusedMonitor?.name)) || Quickshell.screens[0]
    readonly property string layoutLabel: layout.toLowerCase().includes("russian") ? "RU" : "EN"
    function toggle(name, screen, originX, originWidth) {
        if (name === "media" && !players.player) return;
        // Keep the legacy keyboard shortcut pointed at the Ethernet drop.
        if (name === "connections") name = "ethernet";
        panelScreen = mainScreen;
        if (originX !== undefined) panelOriginX = originX;
        if (originWidth !== undefined) panelOriginWidth = originWidth;
        actionError = "";
        panel = panel === name ? "" : name;
    }
    function gesture(action, timestamp) {
        // Separate shortcut processes can finish out of order. Ignore stale
        // input, including a late hide after release. Timestamps wrap at 2^32.
        if (timestamp) {
            const value = Number(timestamp);
            if (!Number.isFinite(value)) return;
            if (gestureTimestamp >= 0 && (value - gestureTimestamp + 4294967296) % 4294967296 > 2147483648) return;
            if (value === gestureTimestamp && action === "hide" && !superHeld) return;
            gestureTimestamp = value;
        }
        lastGesture = action;
        if (action === "hide") {
            superHeld = true;
        } else if (["show", "visibility", "tap", "launcher", "power", "notifications"].includes(action)) {
            // Restoring the input region can register a hover under a stationary cursor.
            if (superHeld) bar.suppressHoverBriefly();
            superHeld = false;
            if (action === "visibility") pillSuppressed = !pillSuppressed;
            else if (action !== "show") toggle(action === "tap" ? "launcher" : action);
        }
    }
    function fixtureEvent(name, data) { console.warn("FIXTURE", JSON.stringify({event: name, data: data})); }
    function desktop(action) {
        if (fixture) { fixtureEvent("desktop", {action: action}); return; }
        Quickshell.execDetached([helper, "desktop", action]);
    }
    function power(action) {
        if (fixture) { fixtureEvent("power", {action: action}); return; }
        actionProcess.command = [backend, "shell", "power", action];
        actionProcess.running = true;
    }
    function loadFixture() {
        if (!fixture) return;
        try {
            fixtureData = JSON.parse(fixtureFile.text());
            layout = fixtureData.layout || "English (US)";
            if (fixtureData.notifications) notifications.entries = fixtureData.notifications;
        } catch (e) { console.warn("Invalid shell fixture:", e); }
    }
    ShellTheme { id: palette }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    OsdState { id: osd }
    Audio {
        id: sound; fixture: root.fixture; fixtureData: root.fixtureData
        deviceControlsOpen: root.panel === "mixer" || root.panel === "bluetooth"
        onFixtureMicMuteRequested: muted => root.fixtureData = Object.assign({}, root.fixtureData, {micMuted: muted})
        onOsdRequested: microphone => osd.showAudio(microphone, microphone ? micVolume : volume, microphone ? micMuted : muted)
    }
    KeyboardLayout { id: keyboardLayoutController; shell: root }
    Applications { id: appIndex; shell: root }
    Media { id: players; shell: root }
    MusicLevels { id: music; shell: root; active: bar.musicEffect }
    ScreenSharing {
        id: sharing; fixture: root.fixture; fixtureData: root.fixtureData
        onFixtureSharesStopped: remainingSources => root.fixtureData = Object.assign({}, root.fixtureData, {screenSources: remainingSources})
    }
    Brightness { id: monitorBrightness; shell: root }
    SystemStats { id: systemStats; shell: root }
    Appearance { id: systemAppearance; shell: root }
    PortalController { id: portalController; shell: root }
    CredentialController { id: credentialController; shell: root }
    Notifications {
        id: notifications
        singlePopup: false
        centerOpen: root.panel === "notifications"
        presentationPaused: root.bannersHidden || centerOpen
        bannerHovered: overlays.banners.hoverHeld
        statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dotfiles/hyprland/notifications.json"
    }
    BluetoothController { id: bluetoothController; shell: root }
    VpnController { id: vpnController; shell: root }
    Agenda { id: agenda; shell: root }
    Weather { id: weather; shell: root }
    property string wallpaperSource: "wallpaper.jpg"
    FileView {
        id: wallpaperState
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dotfiles/hyprland/wallpaper.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        function sync() {
            try {
                const parsed = JSON.parse(text());
                if (typeof parsed.background === "string" && parsed.background.length > 0) {
                    root.wallpaperSource = "file://" + parsed.background;
                    return;
                }
            } catch (error) {}
            root.wallpaperSource = "wallpaper.jpg";
        }
        onLoaded: sync()
        onFileChanged: reload()
        onLoadFailed: root.wallpaperSource = "wallpaper.jpg"
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.namespace: "dotfiles-wallpaper"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Image {
                anchors.fill: parent
                source: root.wallpaperSource
                fillMode: Image.PreserveAspectCrop
                clip: true
            }
        }
    }
    Variants {
        model: Quickshell.screens
        ScreenCorners {
            required property var modelData
            screen: modelData
            topRounded: screen.y === root.desktopTop
            bottomRounded: screen.y + screen.height === root.desktopBottom
            radius: palette.screenCornerRadius
        }
    }
    Bar { id: bar; screen: root.mainScreen; shell: root; theme: palette }
    PillTheme { id: overlayColors }
    ClipboardPopup { id: clipboardPopup; shell: root; theme: bar.pillTheme }
    Overlays { id: overlays; shell: root; theme: overlayColors; showOsd: false }
    Authentication { id: authenticationController; shell: root }
    CaptureEndpoint {
        endpoint: "dotfiles-capture-shell.sock"
        onRequest: (message, client) => {
            if (message.action !== "capture" || typeof message.active !== "boolean") return;
            root.captureClient = message.active ? client : null;
            root.captureActive = message.active;
            reply(client, {id: message.id, accepted: true});
        }
        onDisconnected: client => {
            if (client !== root.captureClient) return;
            root.captureClient = null;
            root.captureActive = false;
        }
    }
    IpcHandler {
        target: "shell"
        function toggle(panel: string): void { if (["launcher", "notifications", "calendar", "power", "connections", "ethernet", "bluetooth", "vpn", "media", "mixer", "system", "weather"].includes(panel)) root.toggle(panel); }
        function clipboard(position: string): void {
            try { clipboardPopup.toggle(JSON.parse(position)); }
            catch (error) { console.warn("Invalid clipboard position:", error); }
        }
        function gesture(action: string, timestamp: string): void { root.gesture(action, timestamp); }
        function capture(active: bool): void { root.captureClient = null; root.captureActive = active; }
        function applications(): string {
            const pane = root.panel === "launcher" ? bar.activePane : null;
            return JSON.stringify({helper: root.helper, open: !!pane, count: pane ? pane.apps.length : 0, loading: pane ? pane.loading : false, error: pane ? pane.error : ""});
        }
        function services(): string {
            return JSON.stringify({applications: appIndex.apps.length, players: players.players.length, outputs: sound.outputs.length, inputs: sound.inputs.length, retained: Object.keys(bar.retained), statistics: systemStats.sample, brightness: monitorBrightness.devices});
        }
        function brightness(output: string, current: int, maximum: int): void { osd.showBrightness(output, current, maximum); }
        function status(): string { return JSON.stringify({pill: bar.pillState, lastGesture: root.lastGesture, pillHidden: root.pillHidden, panel: root.panel, unread: notifications.unread, dnd: notifications.dnd, popups: notifications.popups.length, notifications: notifications.entries.length, volume: sound.volume, muted: sound.muted, osd: osd.visible, osdKind: osd.kind, osdLevel: osd.level, osdOutput: osd.output, layout: root.layout, screenSharing: root.screenSharing, fixture: root.fixture, polkit: !!(authenticationController.agent && authenticationController.agent.isRegistered)}); }
    }
    FileView { id: fixtureFile; path: Quickshell.env("DOTFILES_SHELL_FIXTURE") || ""; blockLoading: true; watchChanges: root.fixture; printErrors: false; onFileChanged: reload(); onLoaded: root.loadFixture() }
    Component.onCompleted: { loadFixture(); if (!fixture) appIndex.refresh(); }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindowv2" && event.data && root.panel) {
                bar.applicationFocused();
            }
            if (event.name === "custom" && event.data.startsWith("dotfiles-pill,")) {
                const parts = event.data.split(",");
                root.gesture(parts[1], parts[2] || "");
                return;
            }
            if (event.name === "workspacev2" && !root.panel && (!bar.expanded || bar.desktopExpanded)) {
                const comma = event.data.indexOf(",");
                const identity = comma >= 0 ? event.data.slice(0, comma) : event.data;
                const workspace = Hyprland.workspaces.values.find(w => String(w.id) === identity);
                osd.showWorkspace(comma >= 0 ? event.data.slice(comma + 1) : event.data,
                    workspace?.monitor?.name || root.focusedScreen?.name || "", identity);
                return;
            }
        }
    }
    Process {
        id: actionProcess
        onExited: (code, status) => { if (code !== 0) { root.actionError = "The action could not be completed."; root.panel = "power"; } }
    }
}
