import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    objectName: "launcherProviders"
    required property var shell
    property string query: ""
    property int generation: 0
    property var quick: []
    property var files: []
    property bool ready: false
    property bool waitingQuick: false
    property bool waitingFiles: false
    readonly property bool loading: waitingQuick || waitingFiles
    property string notice: ""
    property string fileNotice: ""
    property string actionMessage: ""
    property string actionError: ""
    property bool actionPending: false
    property string pendingToken: ""
    property var favorites: ({})
    readonly property string path: shell.helper
    readonly property bool active: shell.panel === "launcher"
    signal actionFinished(string message, bool close)

    function search(text) {
        query = text;
        generation++;
        quick = []; files = []; notice = ""; fileNotice = ""; actionMessage = ""; actionError = "";
        waitingQuick = true; waitingFiles = true;
        if (shell.fixture) {
            const data = shell.fixtureData.launcherResults || {};
            quick = data[text] || [];
            files = (shell.fixtureData.launcherFiles || {})[text] || [];
            ready = true; waitingQuick = false; waitingFiles = false;
            return;
        }
        if (!active && !ready) { waitingQuick = false; waitingFiles = false; return; }
        debounce.restart();
    }
    function sendQuery() {
        if (ready && worker.running) worker.write(JSON.stringify({op: "query", id: generation, query: query}) + "\n");
        else if (active && !worker.running) worker.running = true;
    }
    function act(result, action) {
        if (!result || actionPending) return;
        const close = action === "open" || action === "reveal";
        if (shell.fixture) {
            if (action === "favorite") {
                const next = Object.assign({}, favorites);
                next[result.id] = !isFavorite(result); favorites = next;
            }
            shell.fixtureEvent("launcher-action", {id: result.id, action: action});
            actionMessage = action === "favorite" ? "Favorite updated" : action === "copy" ? "Copied" : "Opened";
            actionFinished(actionMessage, close);
            return;
        }
        if (!ready || !worker.running) { actionMessage = "Search is starting; try again in a moment"; return; }
        actionPending = true;
        pendingToken = close ? "close" : action;
        worker.write(JSON.stringify({op: "action", resultId: result.id, action: action, token: pendingToken,
            appId: result.appId || "", name: result.name}) + "\n");
    }
    function isFavorite(result) {
        if (!result) return false;
        return favorites[result.id] !== undefined ? favorites[result.id] : !!result.favorite;
    }
    function response(data) {
        if (data.ready) { ready = true; sendQuery(); return; }
        if (data.action) {
            actionPending = false;
            actionError = data.error || "";
            actionMessage = data.error || data.message || "";
            if (!data.error) {
                const next = Object.assign({}, favorites);
                next[data.resultId] = !!data.favorite; favorites = next;
                actionFinished(actionMessage, data.token === "close");
                // Empty search is the recent/favorites view; refresh it after edits.
                if (!query) search(query);
            }
            return;
        }
        if (data.id !== generation) return;
        if (data.section === "quick") { quick = data.results || []; waitingQuick = false; notice = data.notice || ""; }
        if (data.section === "files") { files = data.results || []; waitingFiles = false; fileNotice = data.notice || ""; }
    }
    onActiveChanged: {
        if (active) { idle.stop(); search(query); }
        else idle.restart();
    }
    Timer { id: debounce; interval: 80; onTriggered: root.sendQuery() }
    Timer { id: idle; interval: 120000; onTriggered: { if (!root.active) { worker.running = false; root.ready = false; } } }
    Process {
        id: worker
        command: [root.path, "launcher"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try { root.response(JSON.parse(line)); }
                catch (error) { console.warn("Launcher response:", error); }
            }
        }
        stderr: SplitParser { onRead: line => console.warn("Launcher:", line) }
        onExited: (code, status) => {
            root.ready = false; root.actionPending = false;
            root.waitingQuick = false; root.waitingFiles = false;
            if (code !== 0 && root.active) root.notice = "Search stopped; type to retry";
        }
    }
}
