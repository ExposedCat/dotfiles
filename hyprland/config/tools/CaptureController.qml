import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "CaptureGeometry.js" as Geometry

Scope {
    id: root
    ShellTheme { id: typography }
    property bool persistent: false
    property bool active: false
    property bool opening: false
    property bool finishing: false
    property bool finishAfterSettings: false
    property bool warmed: false
    property string sessionDirectory: ""
    property var firstFrames: ({})
    property var data: ({ outputs: [], mode: "region", selection: null })
    property string current: ""
    property bool includeCursor: false
    property var selection: ({x: 0, y: 0, width: 0, height: 0})
    property var strokes: []
    property var draft: null
    property bool dragging: false
    property string tool: ""
    property color ink: "#cc7855"
    property var preferences: ({})
    property string savedPreferences: ""
    readonly property var desktopBounds: data.outputs.length ? Geometry.bounds(data.outputs) : ({x: 0, y: 0, width: 0, height: 0})
    readonly property bool selected: Geometry.valid(selection)
    property bool recording: false
    property bool exporting: false
    property var heldKeys: ({})
    property bool closePending: false
    property bool recordPending: false
    property string error: ""
    property var recordArguments: []
    property var recordSelection: ({ monitor: "", x: 0, y: 0, width: 0, height: 0 })
    readonly property string helper: Quickshell.env("DOTFILES_DESKTOP_BINARY") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hypr/bin/dotfiles-desktop"
    property string shellConfig: Quickshell.shellDir + "/../shell/shell.qml"
    readonly property string defaultShellConfig: Quickshell.shellDir + "/../shell/shell.qml"
    property bool handoffPending: false
    property bool handoffValue: false
    property int handoffId: 0
    property var shellConnection: null
    readonly property bool handoffReady: !!shellConnection?.connected

    function connectShell() {
        const old = shellConnection;
        shellConnection = null;
        if (old) old.destroy();
        // Recreate after connection failure: older Quickshell releases cannot
        // reconnect the same Socket after ServerNotFoundError.
        shellConnection = shellConnectionFactory.createObject(root);
    }

    function handoff(active) {
        handoffValue = active;
        handoffId++;
        handoffPending = true;
        if (shellConfig !== defaultShellConfig) { legacyHandoff(); return; }
        if (handoffReady) { handoffTimeout.restart(); sendHandoff(); }
        else { legacyHandoff(); connectShell(); }
    }
    function sendHandoff() {
        if (!handoffPending) return;
        shellConnection.write(JSON.stringify({action: "capture", active: handoffValue, id: handoffId}) + "\n");
        shellConnection.flush();
    }
    function legacyHandoff() {
        if (!handoffPending) return;
        handoffPending = false;
        handoffTimeout.stop();
        shellHandoff.command = ["/usr/bin/quickshell", "ipc", "--path", shellConfig, "call", "shell", "capture", String(handoffValue)];
        shellHandoff.running = true;
    }
    function handoffComplete() {
        handoffPending = false;
        handoffTimeout.stop();
        if (root.opening) { root.opening = false; root.active = true; }
        else if (root.finishing) root.finishSession();
    }

    function openSession(directory) {
        if (active || opening || finishing || handoffPending || shellHandoff.running || exporter.running || recorder.running || !directory) return false;
        sessionDirectory = directory;
        try {
            sessionFile.reload();
            const next = JSON.parse(sessionFile.text());
            if (!next.outputs || !next.outputs.length) return false;
            error = ""; recording = false; exporting = false; firstFrames = ({});
            heldKeys = ({}); closePending = false; recordPending = false;
            preferences = next.preferences || preferences;
            includeCursor = !!preferences.cursor;
            const saved = next.selection || preferences[next.mode];
            let rect = saved;
            if (saved && saved.monitor) {
                const output = next.outputs.find(o => o.name === saved.monitor);
                rect = output ? {x: output.x + saved.x, y: output.y + saved.y, width: saved.width, height: saved.height} : null;
            }
            selection = Geometry.restore(rect, next.outputs);
            strokes = []; draft = null; dragging = false; tool = "";
            current = (next.outputs.find(o => o.focused) || next.outputs[0]).name;
            data = next;
            // Acknowledge the shell's focus suspension before mapping the
            // exclusive selector, so an open launcher remains in the capture.
            opening = true;
            handoff(true);
            return true;
        } catch (error) { console.warn("Could not open capture session:", error); return false }
    }
    function remember() {
        if (!data.outputs.length) return;
        const next = Object.assign({}, preferences, {cursor: includeCursor});
        if (selected) next[data.mode] = selection;
        preferences = next;
        savePreferences();
    }
    function savePreferences() {
        const value = JSON.stringify(preferences);
        if (settingsWriter.running || value === savedPreferences) return;
        savedPreferences = value;
        settingsWriter.command = [helper, "capture", "preferences", value];
        settingsWriter.running = true;
    }
    function undo() { strokes = strokes.slice(0, -1); }
    function closeSession() {
        if (finishing) return;
        // Keep the exclusive surface until the initiating keys (and modifiers)
        // are released, so the restored app never receives their trailing input.
        if (Object.keys(heldKeys).length || dragging) { closePending = true; return }
        closePending = false; recordPending = false;
        recordDelay.stop();
        active = false;
        recording = false;
        finishing = true;
        handoff(false);
    }
    function finishSession() {
        if (settingsWriter.running) { finishAfterSettings = true; return; }
        finishAfterSettings = false;
        finishing = false;
        if (!persistent) { Qt.quit(); return }
        data = {outputs: [], mode: "region", selection: null};
        resultFile.setText(JSON.stringify({done: true, completedAt: Date.now(), session: sessionDirectory}));
    }
    function logicalKey(key) { return [Qt.Key_Super_L, Qt.Key_Super_R].includes(key) ? Qt.Key_Meta : key; }
    function keyIdentity(key, scanCode) { return scanCode ? "scan:" + scanCode : "key:" + logicalKey(key); }
    function keyPressed(key, modifiers, repeat, scanCode = 0) {
        if (repeat) return;
        const next = Object.assign({}, heldKeys);
        // A layout/group switch can change the symbol before key release.
        // Keep the physical identity so it cannot leave the selector stuck.
        next[keyIdentity(key, scanCode)] = logicalKey(key);
        // Modifiers may already be held when the screenshot overlay opens.
        for (const [flag, code] of [[Qt.ControlModifier, Qt.Key_Control], [Qt.ShiftModifier, Qt.Key_Shift],
                                   [Qt.AltModifier, Qt.Key_Alt], [Qt.MetaModifier, Qt.Key_Meta],
                                   [Qt.GroupSwitchModifier, Qt.Key_AltGr]])
            if ((modifiers & flag) && !Object.values(next).includes(code)) next[keyIdentity(code, 0)] = code;
        heldKeys = next;
    }
    function keyReleased(key, repeat, scanCode = 0) {
        if (repeat) return;
        const next = Object.assign({}, heldKeys);
        delete next[keyIdentity(key, scanCode)];
        // Also release a modifier inferred from the first event's flags.
        delete next[keyIdentity(key, 0)];
        heldKeys = next;
        if (closePending || recordPending) Qt.callLater(finishInput);
    }
    function finishInput() {
        if (Object.keys(heldKeys).length || dragging) return;
        if (closePending) closeSession();
        else if (recordPending) startRecording();
    }
    function noteFrame(name) {
        if (!active || firstFrames[name]) return;
        const frames = Object.assign({}, firstFrames); frames[name] = Date.now(); firstFrames = frames;
    }

    function beginRecording() {
        const left = Math.round(selection.x), top = Math.round(selection.y);
        const w = Math.floor(selection.width / 2) * 2, h = Math.floor(selection.height / 2) * 2;
        if (w < 2 || h < 2) return;
        remember();
        recordSelection = { x: left, y: top, width: w, height: h };
        recordArguments = [helper, "capture", "--session", sessionDirectory, "record", "desktop",
                           String(left), String(top), String(w), String(h), includeCursor ? "yes" : "no"];
        if (Object.keys(heldKeys).length) recordPending = true;
        else startRecording();
    }
    function startRecording() { recordPending = false; recording = true; handoff(false); recordDelay.start(); }
    function exportImage(item, scale) {
        if (exporting) return;
        exporting = true;
        error = "";
        remember();
        // grabToImage's target size is multiplied by the source window's DPR.
        // Request the desired composite pixel size once, on any hosting output.
        const pixelRatio = item.Screen.devicePixelRatio || 1;
        item.grabToImage(result => {
            if (!result.saveToFile(data.render)) {
                error = "Could not render the selected image.";
                exporting = false;
                return;
            }
            exporter.running = true;
        }, Qt.size(Math.max(1, Math.round(item.width * scale / pixelRatio)), Math.max(1, Math.round(item.height * scale / pixelRatio))));
    }

    Process {
        id: settingsWriter
        onExited: (code, status) => {
            if (code !== 0) savedPreferences = "";
            else root.savePreferences();
            if (root.finishAfterSettings && !running) root.finishSession();
        }
    }

    FileView {
        id: sessionFile
        path: root.sessionDirectory ? root.sessionDirectory + "/session.json" : ""
        blockLoading: true
        blockAllReads: true
    }
    FileView { id: resultFile; path: root.sessionDirectory ? root.sessionDirectory + "/result.json" : ""; preload: false; blockWrites: true; atomicWrites: true; printErrors: false }
    Component.onCompleted: {
        connectShell();
        if (!persistent && !openSession(Quickshell.env("DOTFILES_CAPTURE_SESSION"))) Qt.quit();
    }
    IpcHandler {
        target: "capture"
        function open(directory: string): bool { return root.openSession(directory) }
        function cancel(): void { if (root.active && !root.recording) root.closeSession() }
        function recordingStopped(): void { if (root.recording) { root.active = false; root.recording = false; } }
        function status(): string { return JSON.stringify({active: root.active || root.opening || root.finishing || recorder.running, ready: !root.persistent || root.warmed, fastHandoff: root.handoffReady, outputs: root.data.outputs.length, frames: root.firstFrames}) }
    }
    CaptureEndpoint {
        endpoint: root.persistent ? "dotfiles-capture.sock" : ""
        onRequest: (message, client) => {
            if (message.action !== "open" || typeof message.directory !== "string") return;
            const accepted = root.openSession(message.directory);
            reply(client, {accepted: accepted, pid: Quickshell.processId});
        }
    }
    Component {
        id: shellConnectionFactory
        Socket {
            id: connection
            path: Quickshell.env("XDG_RUNTIME_DIR") + "/dotfiles-capture-shell.sock"
            connected: true
            onConnectionStateChanged: {
                if (root.shellConnection !== connection) return;
                if (connected) root.sendHandoff();
                else if (root.handoffPending) root.legacyHandoff();
            }
            onError: { if (root.shellConnection === connection) root.legacyHandoff(); }
            parser: SplitParser {
                onRead: line => {
                    if (root.shellConnection !== connection) return;
                    try {
                        const result = JSON.parse(line);
                        if (root.handoffPending && result.id === root.handoffId && result.accepted) root.handoffComplete();
                    } catch (error) { root.legacyHandoff(); }
                }
            }
        }
    }
    Timer { id: handoffTimeout; interval: 200; onTriggered: root.legacyHandoff() }
    Process {
        id: shellHandoff
        // Standalone captures also work when the desktop shell is absent.
        onExited: root.handoffComplete()
    }
    // Initialize the scene graph once at login, rather than on the first Print.
    // The single transparent pixel has no input region or keyboard focus and
    // is unmapped after its first frame. No selection surface remains visible.
    PanelWindow {
        id: warmup
        visible: root.persistent && !root.warmed && !root.active && Quickshell.screens.length > 0
        anchors { top: true; left: true }
        implicitWidth: 1; implicitHeight: 1
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "dotfiles-capture-warmup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Connections { target: warmup.contentItem.Window.window; function onFrameSwapped() { root.warmed = true } }
    }
    Process {
        id: exporter
        command: [root.helper, "capture", "--session", root.sessionDirectory, "export"]
        onExited: (code, status) => {
            root.exporting = false;
            if (code === 0) root.closeSession();
            else root.error = "Could not save/copy the image. Your selection is still available.";
        }
    }
    Timer {
        id: recordDelay
        interval: 180
        onTriggered: { recorder.command = root.recordArguments; recorder.running = true }
    }
    Process {
        id: recorder
        onExited: (code, status) => {
            if (code === 0) root.closeSession();
            else { root.recording = false; root.error = "Recording failed. Check dotfiles-hyprland-record.service in the user journal." }
        }
    }
    Variants {
        // Build the controls once per connected screen, including while idle.
        // Replacing session output objects used to rebuild every surface on Print.
        model: Quickshell.screens
        delegate: CaptureSurface {
            required property var modelData
            controller: root
            display: root.data.outputs.find(o => o.name === modelData.name)
                || ({name: modelData.name, x: 0, y: 0, width: 0, height: 0, scale: 1, plain: "", cursor: ""})
        }
    }
    Variants {
        model: root.recording ? root.data.outputs : []
        delegate: RecordingShade {
            required property var modelData
            display: modelData
            selection: root.recordSelection
        }
    }
}
