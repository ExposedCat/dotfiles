import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property var shell
    property bool systemDark: true
    property bool ready: false
    property string error: ""
    readonly property bool dark: shell.fixture ? shell.fixtureData.darkMode !== false : systemDark
    readonly property bool available: shell.fixture || ready
    readonly property bool pending: writer.running
    function toggle() {
        if (!available || pending) return;
        error = "";
        if (shell.fixture) {
            const next = !dark;
            shell.fixtureData = Object.assign({}, shell.fixtureData, {darkMode: next});
            shell.fixtureEvent("appearance", {dark: next});
            return;
        }
        writer.command = [shell.backend, "shell", "appearance-set", dark ? "light" : "dark"];
        writer.running = true;
    }
    Process {
        command: [root.shell.backend, "shell", "appearance-watch"]
        running: !root.shell.fixture
        stdout: SplitParser {
            onRead: line => {
                try { root.systemDark = JSON.parse(line).dark; root.ready = true; }
                catch (e) { console.warn("Invalid appearance status:", e); }
            }
        }
        onExited: (code, status) => { root.ready = false; }
    }
    Process {
        id: writer
        onExited: (code, status) => {
            if (code !== 0) { root.error = "Could not change system appearance."; console.warn(root.error); }
        }
    }
}
