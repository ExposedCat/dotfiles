import QtQuick
import Quickshell

Scope {
    id: root
    required property var shell
    property var data: ({fields: []})
    property var client: null
    property bool submitting: false
    property string returnPanel: ""
    readonly property bool active: !!client
    signal cleared()
    function reset() {
        collapse.stop();
        client = null; submitting = false; returnPanel = ""; data = {fields: []}; cleared();
    }
    function restorePanel() { if (shell.panel === "credentials") shell.panel = returnPanel; }
    function finish(response) {
        if (!active || submitting) return;
        submitting = true;
        if (data.kind === "bluetooth" && response.response !== 0 && data.devicePath) shell.bluetooth.cancelPairing(data.devicePath);
        endpoint.reply(client, {id: data.id, response: response.response, values: response.values || {}, remember: !!response.remember});
        cleared();
        restorePanel();
        collapse.restart();
    }
    CaptureEndpoint {
        id: endpoint
        endpoint: "dotfiles-credentials-shell.sock"
        onRequest: (message, sender) => {
            const request = message.data;
            if (message.action === "update" && sender === root.client && request?.id === root.data.id) {
                root.data = request; return;
            }
            if (message.action !== "open" || !request || !["bluetooth", "network"].includes(request.kind)
                    || typeof request.id !== "string" || !Array.isArray(request.fields) || request.fields.length > 8
                    || root.active || collapse.running || root.shell.captureActive || root.shell.authentication.active || root.shell.portal.active) {
                reply(sender, {accepted: false}); return;
            }
            root.returnPanel = request.kind === "bluetooth" && root.shell.panel === "bluetooth" ? "bluetooth" : "";
            if (root.returnPanel) {
                const device = root.shell.bluetooth.devices.find(d => d.dbusPath === request.devicePath);
                if (device) root.shell.pill.activePane?.selectDevice(device.address);
            }
            root.client = sender; root.data = request; root.submitting = false;
            root.shell.superHeld = false; root.shell.panel = "credentials";
            reply(sender, {accepted: true});
        }
    }
    Connections {
        target: root.shell
        function onPanelChanged() { if (root.active && root.shell.panel !== "credentials" && !root.submitting) root.finish({response: 1}); }
    }
    Connections {
        target: root.client
        function onConnectionStateChanged() {
            if (root.client && !root.client.connected) {
                if (root.submitting) { root.client = null; return; }
                root.submitting = true;
                root.restorePanel();
                root.reset();
            }
        }
    }
    Timer { id: collapse; interval: 230; onTriggered: root.reset() }
}
