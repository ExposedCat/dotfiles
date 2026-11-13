import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    ShellTheme { id: typography }
    property bool persistent: false
    property bool active: false
    property bool warmed: false
    property string sessionDirectory: ""
    property var firstFrames: ({})
    property var data: ({ outputs: [], mode: "region", selection: null })
    property string current: ""
    property bool includeCursor: false
    property bool recording: false
    property bool exporting: false
    property string error: ""
    property var recordArguments: []
    property var recordSelection: ({ monitor: "", x: 0, y: 0, width: 0, height: 0 })
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("capture.py").toString().replace(/^file:\/\//, ""))

    function openSession(directory) {
        if (active || exporter.running || recorder.running || !directory) return false;
        sessionDirectory = directory;
        try {
            const next = JSON.parse(sessionFile.text());
            if (!next.outputs || !next.outputs.length) return false;
            error = ""; recording = false; exporting = false; firstFrames = ({});
            current = next.selection ? next.selection.monitor : (next.outputs.find(o => o.focused) || next.outputs[0]).name;
            data = next;
            active = true;
            return true;
        } catch (error) { console.warn("Could not open capture session:", error); return false }
    }
    function closeSession() {
        if (!persistent) { Qt.quit(); return }
        active = false;
        recording = false;
        data = {outputs: [], mode: "region", selection: null};
        resultFile.setText(JSON.stringify({done: true, completedAt: Date.now(), session: sessionDirectory}));
    }
    function noteFrame(name) {
        if (!active || firstFrames[name]) return;
        const frames = Object.assign({}, firstFrames); frames[name] = Date.now(); firstFrames = frames;
    }

    function beginRecording(display, x, y, width, height) {
        const left = Math.max(0, Math.round(x)), top = Math.max(0, Math.round(y));
        const w = Math.floor(Math.min(Math.round(width), display.width - left) / 2) * 2;
        const h = Math.floor(Math.min(Math.round(height), display.height - top) / 2) * 2;
        if (w < 2 || h < 2) return;
        recordSelection = { monitor: display.name, x: left, y: top, width: w, height: h };
        recordArguments = ["python3", helper, "--session", sessionDirectory, "record", display.name,
                           String(left), String(top), String(w), String(h), includeCursor ? "yes" : "no"];
        recording = true;
        recordDelay.start();
    }
    function exportImage(item, scale) {
        if (exporting) return;
        exporting = true;
        error = "";
        item.grabToImage(result => {
            if (!result.saveToFile(data.render)) {
                error = "Could not render the selected image.";
                exporting = false;
                return;
            }
            exporter.running = true;
        }, Qt.size(Math.max(1, Math.round(item.width * scale)), Math.max(1, Math.round(item.height * scale))));
    }

    FileView {
        id: sessionFile
        path: root.sessionDirectory ? root.sessionDirectory + "/session.json" : ""
        blockLoading: true
        blockAllReads: true
    }
    FileView { id: resultFile; path: root.sessionDirectory ? root.sessionDirectory + "/result.json" : ""; preload: false; blockWrites: true; atomicWrites: true; printErrors: false }
    Component.onCompleted: {
        if (!persistent && !openSession(Quickshell.env("DOTFILES_CAPTURE_SESSION"))) Qt.quit();
    }
    IpcHandler {
        target: "capture"
        function open(directory: string): bool { return root.openSession(directory) }
        function cancel(): void { if (root.active && !root.recording) root.closeSession() }
        function status(): string { return JSON.stringify({active: root.active, ready: !root.persistent || root.warmed, outputs: root.data.outputs.length, frames: root.firstFrames}) }
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
        command: ["python3", root.helper, "--session", root.sessionDirectory, "export"]
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
    Process { id: stopRecorder; command: ["python3", root.helper, "stop"] }
    Variants {
        model: root.data.outputs
        delegate: CaptureSurface {
            required property var modelData
            controller: root
            display: modelData
        }
    }
    // On this two-display setup, put the stop control on the other display so
    // the recording contains neither the selector nor its recording controls.
    Variants {
        model: root.recording ? root.data.outputs : []
        delegate: RecordingShade {
            required property var modelData
            display: modelData
            selection: root.recordSelection
        }
    }
    Variants {
        // Map after the shades, above them in the overlay layer.
        model: root.recording && recorder.running ? root.data.outputs.filter(o => o.name !== root.current).slice(0, 1) : []
        delegate: PanelWindow {
            required property var modelData
            screen: Quickshell.screens.find(s => s.name === modelData.name) || Quickshell.screens[0]
            anchors { top: true }
            margins.top: 16
            implicitWidth: 300
            implicitHeight: 44
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "dotfiles-record-status"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            Rectangle {
                anchors.fill: parent
                color: "#1e1e2e"
                radius: 12
                border.color: "#f38ba8"
                Text { font.family: typography.fontFamily; font.weight: typography.fontWeight; font.pixelSize: typography.bodySize; anchors.centerIn: parent; text: "● Recording · click to stop"; color: "#f38ba8" }
                MouseArea { anchors.fill: parent; onClicked: stopRecorder.running = true }
            }
        }
    }
}
