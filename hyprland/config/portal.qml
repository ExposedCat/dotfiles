import QtQuick
import Quickshell
import Quickshell.Io
import "shell" as Desktop

Scope {
    id: root
    property var data: ({kind: "apps", apps: []})
    property bool ready: false
    property bool submitting: false
    property real reveal: 0
    readonly property string directory: Quickshell.env("DOTFILES_PORTAL_REQUEST") || ""
    readonly property string helper: Quickshell.env("DOTFILES_DESKTOP_BINARY") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hypr/bin/dotfiles-desktop"
    function choose(identity) { content.choose(identity); }
    function load() {
        try {
            data = JSON.parse(request.text());
            if (!ready) { ready = true; content.activate(); opening.start(); }
        } catch (error) { content.error = "Could not load the request."; }
    }
    function decide(response) {
        if (submitting) return;
        submitting = true;
        writer.command = [helper, "portal", "respond", directory, JSON.stringify(response)];
        opening.stop(); closing.start();
    }
    NumberAnimation { id: opening; target: root; property: "reveal"; to: 1; duration: 150; easing.type: Easing.OutCubic }
    NumberAnimation { id: closing; target: root; property: "reveal"; to: 0; duration: 90; easing.type: Easing.InCubic; onFinished: writer.running = true }
    FileView { id: request; path: root.directory + "/request.json"; watchChanges: true; blockLoading: true; onLoaded: root.load(); onFileChanged: reload() }
    Process {
        id: writer
        onExited: (code, status) => { if (code === 0) Qt.quit(); else { root.submitting = false; content.error = "Could not send the response."; opening.start(); } }
    }
    Desktop.PillTheme { id: portalTheme }
    FloatingWindow {
        title: "Desktop portal: " + (root.data.kind === "share" ? "Screen sharing" : root.data.kind === "access" ? "Permission" : "Open With")
        implicitWidth: content.desiredWidth; implicitHeight: content.desiredHeight
        minimumSize: Qt.size(implicitWidth, implicitHeight); maximumSize: minimumSize
        color: "transparent"; visible: root.ready
        onClosed: root.decide({response: 1})
        Shortcut { sequence: "Escape"; context: Qt.WindowShortcut; autoRepeat: false; enabled: !root.submitting; onActivated: root.decide({response: 1}) }
        Item {
            anchors.fill: parent; opacity: root.reveal; scale: 0.97 + root.reveal * 0.03
            Desktop.PillBackground { anchors.fill: parent; theme: portalTheme; radius: 20 }
            Desktop.PortalDialog {
                id: content
                anchors.fill: parent
                anchors.leftMargin: sharing || permission ? 18 : 12
                anchors.rightMargin: anchors.leftMargin
                anchors.topMargin: sharing || permission ? 18 : 8
                anchors.bottomMargin: sharing || permission ? 18 : 12
                theme: portalTheme; requestData: root.data; submitting: root.submitting
                onResponded: response => root.decide(response)
            }
        }
    }
}
