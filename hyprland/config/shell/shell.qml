import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root
    readonly property bool fixture: !!Quickshell.env("DOTFILES_SHELL_FIXTURE")
    property var fixtureData: ({})
    property string panel: ""
    property bool pillHidden: false
    property real gestureTimestamp: -1
    property string lastGesture: ""
    property real panelOriginX: 0
    property real panelOriginWidth: 56
    property alias bluetooth: bluetoothController
    property var panelScreen: null
    property string layout: "English (US)"
    property string keyboard: ""
    property bool recording: false
    property string actionError: ""
    property alias audio: sound
    property alias osd: osd
    property alias notifications: notifications
    property alias clock: clock
    property alias agenda: agenda
    property alias pill: bar
    property alias overlays: overlays
    property alias applications: appIndex
    property alias media: players
    property alias brightness: monitorBrightness
    property alias stats: systemStats
    property bool emberEnabled: true
    readonly property var emberTarget: bar.emberTarget
    // HP OMEN is the main display. Fall back gracefully if it is disconnected.
    readonly property string mainOutput: fixture ? (fixtureData.mainOutput || "X11-1") : "DP-3"
    readonly property var mainScreen: Quickshell.screens.find(s => s.name === mainOutput) || Quickshell.screens[0]
    readonly property real desktopTop: Math.min(...Quickshell.screens.map(s => s.y))
    readonly property real desktopBottom: Math.max(...Quickshell.screens.map(s => s.y + s.height))
    // Resolving a URL above Quickshell's config root returns qs-blackhole.
    // Resolve this component's directory, then construct a filesystem path.
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")) + "/../tools/desktop.py"
    readonly property string backend: decodeURIComponent(Qt.resolvedUrl("shell.py").toString().replace(/^file:\/\//, ""))
    readonly property var focusedScreen: fixture ? Quickshell.screens[0] : Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    readonly property string layoutLabel: layout.toLowerCase().includes("russian") ? "RU" : "EN"
    function toggle(name, screen, originX, originWidth) {
        // Keep the legacy keyboard shortcut pointed at the Ethernet drop.
        if (name === "connections") name = "ethernet";
        panelScreen = mainScreen;
        if (originX !== undefined) panelOriginX = originX;
        if (originWidth !== undefined) panelOriginWidth = originWidth;
        actionError = "";
        panel = panel === name ? "" : name;
        if (panel === "notifications") notifications.markRead();
    }
    function gesture(action, timestamp) {
        // Separate shortcut processes can finish out of order. Ignore stale
        // input, including a late hide after release. Timestamps wrap at 2^32.
        if (timestamp) {
            const value = Number(timestamp);
            if (!Number.isFinite(value)) return;
            if (gestureTimestamp >= 0 && (value - gestureTimestamp + 4294967296) % 4294967296 > 2147483648) return;
            if (value === gestureTimestamp && action === "hide" && !pillHidden) return;
            gestureTimestamp = value;
        }
        lastGesture = action;
        if (action === "hide") pillHidden = true;
        else if (action === "show") pillHidden = false;
        else if (action === "tap") { pillHidden = false; toggle("launcher"); }
        else if (["launcher", "power", "notifications"].includes(action)) { pillHidden = false; toggle(action); }
    }
    function fixtureEvent(name, data) { console.warn("FIXTURE", JSON.stringify({event: name, data: data})); }
    function desktop(action) {
        if (fixture) { fixtureEvent("desktop", {action: action}); return; }
        Quickshell.execDetached(["/usr/bin/python3", helper, action]);
    }
    function power(action) {
        if (fixture) { fixtureEvent("power", {action: action}); return; }
        actionProcess.command = ["/usr/bin/python3", backend, "power", action];
        actionProcess.running = true;
    }
    function loadFixture() {
        if (!fixture) return;
        try {
            fixtureData = JSON.parse(fixtureFile.text());
            layout = fixtureData.layout || "English (US)";
            recording = !!fixtureData.recording;
            if (fixtureData.notifications) notifications.entries = fixtureData.notifications;
        } catch (e) { console.warn("Invalid shell fixture:", e); }
    }
    ShellTheme { id: palette }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    OsdState { id: osd }
    Audio {
        id: sound; fixture: root.fixture; fixtureData: root.fixtureData
        mixerOpen: root.panel === "mixer"
        onOsdRequested: microphone => osd.showAudio(microphone, microphone ? micVolume : volume, microphone ? micMuted : muted)
    }
    Applications { id: appIndex; shell: root }
    Media { id: players; shell: root }
    Brightness { id: monitorBrightness; shell: root }
    SystemStats { id: systemStats; shell: root }
    Notifications { id: notifications; singlePopup: false; presentationPaused: root.panel === "notifications"; centerOpen: root.panel === "notifications"; statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dotfiles/hyprland/notifications.json" }
    BluetoothController { id: bluetoothController; shell: root }
    Agenda { id: agenda; shell: root }
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
    Overlays { id: overlays; shell: root; theme: overlayColors; showOsd: false }
    Authentication { id: authentication; shell: root; theme: palette }
    IpcHandler {
        target: "shell"
        function toggle(panel: string): void { if (["launcher", "notifications", "power", "connections", "ethernet", "bluetooth", "media", "mixer", "system"].includes(panel)) root.toggle(panel); }
        function gesture(action: string, timestamp: string): void { root.gesture(action, timestamp); }
        function applications(): string {
            const pane = root.panel === "launcher" ? bar.activePane : null;
            return JSON.stringify({helper: root.helper, open: !!pane, count: pane ? pane.apps.length : 0, loading: pane ? pane.loading : false, error: pane ? pane.error : ""});
        }
        function services(): string {
            return JSON.stringify({applications: appIndex.apps.length, players: players.players.length, outputs: sound.outputs.length, inputs: sound.inputs.length, retained: Object.keys(bar.retained), statistics: systemStats.sample, brightness: monitorBrightness.devices});
        }
        function brightness(output: string, current: int, maximum: int): void { osd.showBrightness(output, current, maximum); }
        function status(): string { return JSON.stringify({pill: bar.pillState, lastGesture: root.lastGesture, pillHidden: root.pillHidden, panel: root.panel, unread: notifications.unread, dnd: notifications.dnd, popups: notifications.popups.length, notifications: notifications.entries.length, volume: sound.volume, muted: sound.muted, osd: osd.visible, osdKind: osd.kind, osdLevel: osd.level, osdOutput: osd.output, layout: root.layout, recording: root.recording, fixture: root.fixture, polkit: !!(authentication.agent && authentication.agent.isRegistered)}); }
    }
    FileView { id: fixtureFile; path: Quickshell.env("DOTFILES_SHELL_FIXTURE") || ""; blockLoading: true; watchChanges: root.fixture; printErrors: false; onFileChanged: reload(); onLoaded: root.loadFixture() }
    Component.onCompleted: { loadFixture(); if (!fixture) appIndex.refresh(); }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "custom" && event.data.startsWith("dotfiles-pill,")) {
                const parts = event.data.split(",");
                root.gesture(parts[1], parts[2] || "");
                return;
            }
            if (event.name === "workspacev2" && !root.panel && !root.pill.expanded) {
                const comma = event.data.indexOf(",");
                osd.showWorkspace(comma >= 0 ? event.data.slice(comma + 1) : event.data);
                return;
            }
            if (event.name !== "activelayout") return;
            const comma = event.data.indexOf(",");
            if (comma >= 0 && (!root.keyboard || event.data.slice(0, comma) === root.keyboard)) root.layout = event.data.slice(comma + 1);
        }
    }
    Process {
        id: watcher
        command: ["/usr/bin/python3", root.backend, "watch"]
        running: !root.fixture
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    if (data.layout !== undefined) root.layout = data.layout;
                    if (data.keyboard !== undefined) root.keyboard = data.keyboard;
                    if (data.recording !== undefined) root.recording = data.recording;
                } catch (e) { console.warn("Invalid desktop status:", e); }
            }
        }
        onExited: { if (!root.fixture) retry.restart(); }
    }
    Timer { id: retry; interval: 3000; onTriggered: watcher.running = true }
    Process {
        id: actionProcess
        onExited: (code, status) => { if (code !== 0) { root.actionError = "The action could not be completed."; root.panel = "power"; } }
    }
}
