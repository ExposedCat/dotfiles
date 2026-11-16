import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "lib/fuzzy.js" as Fuzzy

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    Applications { id: localIndex; shell: root.shell }
    LauncherProviders {
        id: providers; shell: root.shell
        onActionFinished: (message, close) => { root.copied = message === "Copied"; if (close && !root.shell.pill?.launcherDragged) root.shell.panel = ""; }
    }
    readonly property var indexStore: shell.applications || localIndex
    readonly property var installedApps: indexStore.apps
    readonly property var apps: indexStore.apps
    readonly property string error: indexStore.error
    property bool launching: false
    property bool copied: false
    readonly property bool loading: indexStore.loading || providers.loading
    readonly property var matches: Fuzzy.rank(apps, search.text, indexStore.usage)
    readonly property bool filtered: /^(files?|f|chars?|characters?|emoji|symbols?|bookmarks?|bm|web)\s/i.test(search.text) || /^(\/|~\/|file:\/\/)/.test(search.text)
    readonly property var results: combine()
    readonly property var selected: list.currentIndex >= 0 && list.currentIndex < results.length ? results[list.currentIndex] : null
    property string selectedId: ""
    property bool selectionExplicit: false
    property point pointerPosition: Qt.point(-1, -1)
    signal dragStarted(real x, real y)
    signal dragMoved(real x, real y)
    signal dragFinished()
    readonly property Item emberTarget: caretSlot
    spacing: 4
    function combine() {
        const rows = [], seen = {};
        function append(row) { if (!seen[row.id]) { rows.push(row); seen[row.id] = true; } }
        const appRows = filtered ? [] : matches.map(app => {
            const saved = providers.quick.find(row => row.kind === "app" && row.appId === app.id);
            return Object.assign({}, saved || {}, app, {id: "app:" + app.id, appId: app.id, kind: "app"});
        });
        for (const app of appRows) if (Fuzzy.titleScore(app, search.text) < 99) append(app);
        for (const row of providers.quick) {
            const app = row.kind === "app" ? apps.find(a => a.id === row.appId) : null;
            if (row.kind !== "app" || app) append(app ? Object.assign({}, app, row, {icon: app.icon}) : row);
        }
        if (!filtered)
            for (const app of appRows) append(app);
        for (const row of providers.files) append(row);
        return rows;
    }
    function maintainSelection() {
        const found = selectionExplicit ? results.findIndex(row => row.id === selectedId) : -1;
        list.currentIndex = found >= 0 ? found : results.length ? 0 : -1;
        if (selected) selectedId = selected.id;
        if (!selectionExplicit) list.positionViewAtBeginning();
    }
    function choose(index) {
        selectionExplicit = true;
        list.currentIndex = index;
        selectedId = selected ? selected.id : "";
        copied = false; providers.actionMessage = "";
    }
    onResultsChanged: Qt.callLater(maintainSelection)
    function selectFilter(prefix) { search.text = prefix; search.forceActiveFocus(); search.cursorPosition = search.text.length; }
    function defaultAction(row) { return ["app", "file", "bookmark", "web"].includes(row.kind) ? "open" : "copy"; }
    function launch() { if (selected) act(defaultAction(selected)); }
    function act(action) {
        if (!selected) return;
        if (action === "browse" && selected.directory) { selectFilter(selected.path + "/"); return; }
        if (selected.kind === "app" && action === "open") indexStore.record(selected.appId);
        providers.act(selected, action);
    }
    function focusSearch() { search.forceActiveFocus(); }
    function activate() {
        launching = false; copied = false; selectedId = ""; selectionExplicit = false;
        pointerPosition = Qt.point(-1, -1);
        indexStore.refresh();
        if (search.text) search.clear();
        else providers.search("");
        Qt.callLater(focusSearch);
    }
    function moveSelection(delta) {
        choose(Math.max(0, Math.min(list.currentIndex + delta, list.count - 1)));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }
    Component.onCompleted: activate()
    TextField {
        id: search; objectName: "pillSearch"
        Layout.fillWidth: true; implicitHeight: 36; focus: true
        font: root.theme.textFont
        color: root.theme.text
        placeholderText: "Search"; placeholderTextColor: root.theme.secondary
        leftPadding: 50; rightPadding: 60; selectByMouse: true
        cursorVisible: !root.shell.emberEnabled
        background: Item {}
        ShellIcon { x: 13; y: Math.round((parent.height - height) / 2); name: "search"; width: 24; height: 24; opacity: 0.8 }
        EmberSlot { id: caretSlot; shell: root.shell; x: search.cursorRectangle.x; y: search.cursorRectangle.y; width: 3; height: search.cursorRectangle.height || 19; shapeRadius: 1.5; caret: true }
        onTextChanged: {
            root.copied = false; root.selectedId = ""; root.selectionExplicit = false;
            providers.search(text); Qt.callLater(root.maintainSelection);
        }
        Keys.onDownPressed: root.moveSelection(1)
        Keys.onUpPressed: root.moveSelection(-1)
        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && !search.selectedText) {
                root.act("copy"); event.accepted = true;
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_D) {
                root.act("favorite"); event.accepted = true;
            } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.selected?.kind === "file") {
                root.act("reveal"); event.accepted = true;
            } else if (event.key === Qt.Key_Tab && root.selected?.directory) {
                root.act("browse"); event.accepted = true;
            }
        }
        onAccepted: root.launch()
        Accessible.name: "Search"
        Spinner {
            anchors { right: dragHandle.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            visible: root.loading; running: visible; width: 16; height: 16
        }
        Item {
            id: dragHandle; objectName: "launcherDragHandle"
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 26; height: 36; z: 2
            ShellIcon { anchors.centerIn: parent; name: "grip-vertical"; width: 20; height: 20; opacity: grip.containsMouse ? 1 : 0.6 }
            MouseArea {
                id: grip; anchors.fill: parent; hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true
                onPressed: mouse => { mouse.accepted = true; const p = mapToGlobal(mouse.x, mouse.y); root.dragStarted(p.x, p.y); }
                onPositionChanged: mouse => { if (pressed) { const p = mapToGlobal(mouse.x, mouse.y); root.dragMoved(p.x, p.y); } }
                onReleased: { root.dragFinished(); root.focusSearch(); }
                onCanceled: root.dragFinished()
            }
            Accessible.role: Accessible.Grip
            Accessible.name: "Move launcher"
        }
    }
    ListView {
        id: list; objectName: "pillApps"
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 2
        model: root.results; currentIndex: count ? 0 : -1
        boundsBehavior: Flickable.StopAtBounds
        PillWheel { flickable: list }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: LauncherResult {
            theme: root.theme; width: list.width
            selected: ListView.isCurrentItem
            favorite: providers.isFavorite(modelData)
            onPointerMoved: (x, y) => {
                const p = mapToItem(root, x, y);
                if (root.pointerPosition.x >= 0 && (Math.abs(p.x - root.pointerPosition.x) > 0.5 || Math.abs(p.y - root.pointerPosition.y) > 0.5))
                    root.choose(index);
                root.pointerPosition = p;
            }
            onActivated: { root.choose(index); root.launch(); }
        }
        Text {
            anchors.centerIn: parent; width: parent.width - 20; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
            visible: list.count === 0
            text: root.loading ? "" : providers.notice || providers.fileNotice || root.error || "No matches"
            color: root.theme.secondary; font: root.theme.textFont
        }
    }
    Text {
        Layout.fillWidth: true
        visible: !!providers.actionError
        text: providers.actionError; textFormat: Text.PlainText; wrapMode: Text.WordWrap
        font: root.theme.textFont
        color: root.theme.red
    }
}
