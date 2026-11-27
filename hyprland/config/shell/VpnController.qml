import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property var shell
    property var profiles: []
    property bool unavailable: false
    property bool loaded: false
    property var pending: ({})
    property var errors: ({})
    property string activeJobUuid: ""
    property string activeJobAction: ""
    readonly property bool loading: !loaded && reader.running
    readonly property bool active: profiles.some(p => p.active)
    readonly property var activeNames: profiles.filter(p => p.active).map(p => p.name)

    function busy(profile) {
        return !!profile && (!!pending[profile.uuid] || profile.state === "connecting" || profile.state === "disconnecting");
    }

    function update(data) {
        const next = (data.profiles || []).map(p => ({
            uuid: p.uuid,
            name: p.name,
            kind: p.kind || "vpn",
            state: p.state || (p.active ? "connected" : "disconnected"),
            active: !!p.active
        }));
        if (JSON.stringify(next) !== JSON.stringify(profiles)) profiles = next;
        unavailable = !!data.unavailable;
        loaded = true;
    }

    function refresh() {
        if (shell.fixture) {
            update({
                profiles: shell.fixtureData.vpnProfiles || [
                    {uuid: "fixture-vpn-1", name: "FEL", kind: "vpn", state: "disconnected", active: false}
                ],
                unavailable: !!shell.fixtureData.vpnUnavailable
            });
            return;
        }
        if (!reader.running) reader.running = true;
    }

    function toggle(profile) {
        if (!profile || busy(profile) || worker.running || fixtureWorker.running) return;
        const action = profile.active || profile.state === "connecting" ? "down" : "up";
        const nextPending = Object.assign({}, pending);
        nextPending[profile.uuid] = {action: action};
        pending = nextPending;
        const nextErrors = Object.assign({}, errors);
        delete nextErrors[profile.uuid];
        errors = nextErrors;
        activeJobUuid = profile.uuid;
        activeJobAction = action;
        if (shell.fixture) {
            shell.fixtureEvent("vpn", {uuid: profile.uuid, name: profile.name, action: action});
            fixtureWorker.restart();
            return;
        }
        worker.command = [shell.backend, "shell", "vpn", action, profile.uuid];
        worker.running = true;
    }

    function finishJob(code, message) {
        const uuid = activeJobUuid;
        if (uuid) {
            const nextPending = Object.assign({}, pending);
            delete nextPending[uuid];
            pending = nextPending;
            const nextErrors = Object.assign({}, errors);
            if (message) nextErrors[uuid] = message;
            else if (code !== 0 && !nextErrors[uuid]) nextErrors[uuid] = activeJobAction === "down" ? "Could not disconnect." : "Could not connect.";
            else if (code === 0) delete nextErrors[uuid];
            errors = nextErrors;
        }
        activeJobUuid = "";
        activeJobAction = "";
        refresh();
    }

    Component.onCompleted: refresh()

    Connections {
        target: root.shell
        function onPanelChanged() { if (root.shell.panel === "vpn") root.refresh(); }
        function onFixtureDataChanged() { if (root.shell.fixture) root.refresh(); }
    }

    Timer {
        interval: 3000; repeat: true
        running: root.shell.panel === "vpn"
        onTriggered: root.refresh()
    }

    Process {
        id: reader
        command: [root.shell.backend, "shell", "vpn-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.update(data);
                } catch (e) {
                    root.unavailable = true;
                    root.loaded = true;
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.unavailable = true;
                root.loaded = true;
            }
        }
    }

    Process {
        id: worker
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    if (data.error && root.activeJobUuid) {
                        const nextErrors = Object.assign({}, root.errors);
                        nextErrors[root.activeJobUuid] = data.error;
                        root.errors = nextErrors;
                    }
                } catch (e) { /* handled in onExited */ }
            }
        }
        onExited: (code, status) => root.finishJob(code, "")
    }

    Timer {
        id: fixtureWorker
        interval: 400
        onTriggered: {
            const uuid = root.activeJobUuid;
            const connect = root.activeJobAction === "up";
            root.profiles = root.profiles.map(p => p.uuid === uuid
                ? Object.assign({}, p, {active: connect, state: connect ? "connected" : "disconnected"}) : p);
            root.finishJob(0, "");
        }
    }
}
