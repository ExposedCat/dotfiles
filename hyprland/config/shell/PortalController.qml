import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property var shell
    property var data: ({apps: []})
    property string directory: ""
    property var client: null
    property bool presented: false
    property bool submitting: false
    property var response: ({response: 1})
    readonly property bool active: !!directory
    readonly property string helper: shell.helper

    function reset() {
        collapse.stop();
        client = null; directory = ""; presented = false; submitting = false;
        data = {apps: []};
    }
    function load() {
        if (!active || !client) return;
        try {
            const request = JSON.parse(requestFile.text());
            if (!["apps", "access", "share"].includes(request.kind)
                    || (request.kind === "apps" && !Array.isArray(request.apps))) throw Error("Invalid portal request");
            data = request;
            if (!presented) {
                shell.pillHidden = false;
                shell.panel = "portal";
                presented = true;
                endpoint.reply(client, {accepted: true});
            }
        } catch (error) {
            console.warn("Portal request load failed:", error);
            endpoint.reply(client, {accepted: false});
            reset();
        }
    }
    function finish(code, identity) {
        finishResponse(code === 0 ? {response: 0, choice: identity} : {response: code});
    }
    function finishResponse(result) {
        if (!active || submitting) return;
        if (result.response === 0 && data.kind === "apps" && !(data.apps || []).some(app => app.id === result.choice)) return;
        submitting = true;
        response = result;
        if (shell.panel === "portal") shell.panel = "";
        collapse.start();
    }
    CaptureEndpoint {
        id: endpoint
        endpoint: "dotfiles-portal-shell.sock"
        onRequest: (message, sender) => {
            const runtime = Quickshell.env("XDG_RUNTIME_DIR") + "/";
            const directory = message.directory;
            if (message.action !== "open" || typeof directory !== "string" || !directory.startsWith(runtime)
                    || !/^dotfiles-portal-[a-zA-Z0-9_-]+$/.test(directory.slice(runtime.length))
                    || root.active || writer.running || root.shell.captureActive || root.shell.credentials.active) {
                reply(sender, {accepted: false}); return;
            }
            root.client = sender;
            root.directory = directory;
        }
    }
    FileView {
        id: requestFile
        path: root.directory ? root.directory + "/request.json" : ""
        blockLoading: true; watchChanges: true; printErrors: false
        onLoaded: root.load()
        onFileChanged: reload()
        onLoadFailed: { if (root.client) { endpoint.reply(root.client, {accepted: false}); root.reset(); } }
    }
    Connections {
        target: root.shell
        function onPanelChanged() { if (root.presented && root.shell.panel !== "portal") root.finish(1); }
    }
    Connections {
        target: root.client
        function onConnectionStateChanged() {
            if (root.client && !root.client.connected) {
                collapse.stop();
                root.presented = false;
                if (root.shell.panel === "portal") root.shell.panel = "";
                root.reset();
            }
        }
    }
    Timer {
        id: collapse; interval: 230
        onTriggered: {
            writer.command = [root.helper, "portal", "respond", root.directory, JSON.stringify(root.response)];
            writer.running = true;
        }
    }
    Process {
        id: writer
        onExited: (code, status) => {
            if (!root.active) return;
            if (root.client) endpoint.reply(root.client, {done: true});
            if (code !== 0) console.warn("Could not write the pill chooser response");
            root.reset();
        }
    }
}
