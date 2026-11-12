import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    property var data: ({ outputs: [], mode: "region", selection: null })
    property string current: ""
    property bool includeCursor: false
    property bool recording: false
    property bool exporting: false
    property string error: ""
    property var recordArguments: []
    property var recordSelection: ({ monitor: "", x: 0, y: 0, width: 0, height: 0 })
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("capture.py").toString().replace(/^file:\/\//, ""))

    function beginRecording(display, x, y, width, height) {
        const left = Math.max(0, Math.round(x)), top = Math.max(0, Math.round(y));
        const w = Math.floor(Math.min(Math.round(width), display.width - left) / 2) * 2;
        const h = Math.floor(Math.min(Math.round(height), display.height - top) / 2) * 2;
        if (w < 2 || h < 2) return;
        recordSelection = { monitor: display.name, x: left, y: top, width: w, height: h };
        recordArguments = ["python3", helper, "record", display.name,
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
        path: Quickshell.env("DOTFILES_CAPTURE_SESSION") + "/session.json"
        blockLoading: true
    }
    Component.onCompleted: {
        const data = JSON.parse(sessionFile.text());
        current = data.selection ? data.selection.monitor : (data.outputs.find(o => o.focused) || data.outputs[0]).name;
        root.data = data;
    }
    Process {
        id: exporter
        command: ["python3", root.helper, "export"]
        onExited: (code, status) => {
            root.exporting = false;
            if (code === 0) Qt.quit();
            else root.error = "Could not save/copy the image. Your selection is still available.";
        }
    }
    Timer {
        id: recordDelay
        interval: 180
        onTriggered: { recorder.command = root.recordArguments; recorder.running = true; }
    }
    Process {
        id: recorder
        onExited: (code, status) => {
            if (code === 0) Qt.quit();
            else { root.recording = false; root.error = "Recording failed. Check dotfiles-hyprland-record.service in the user journal."; }
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
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.namespace: "dotfiles-record-status"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            Rectangle {
                anchors.fill: parent
                color: "#1e1e2e"
                radius: 12
                border.color: "#f38ba8"
                Text { anchors.centerIn: parent; text: "● Recording · click to stop"; color: "#f38ba8"; font.pixelSize: 15 }
                MouseArea { anchors.fill: parent; onClicked: stopRecorder.running = true }
            }
        }
    }
}
