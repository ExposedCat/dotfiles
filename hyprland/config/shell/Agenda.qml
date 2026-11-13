import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property var shell
    property date selectedDate: shell.clock.date
    readonly property string selectedKey: dayKey(selectedDate)
    property string requestedKey: ""
    property var cache: ({})
    readonly property var events: cache[selectedKey] ? cache[selectedKey].events : []
    readonly property bool cached: !!cache[selectedKey]
    property var clocks: []
    property bool configured: false
    property bool loading: false
    property bool unavailable: false
    property bool ready: false
    readonly property string cachePath: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/dotfiles/hyprland/agenda.json"
    function dayKey(date) { return Qt.formatDateTime(date, "yyyy-MM-dd"); }
    function selectDate(date) { selectedDate = date; }
    function saveDay(key, events) {
        const next = Object.assign({}, cache);
        next[key] = {events: events, updated: Date.now()};
        const keys = Object.keys(next).sort((a,b) => next[b].updated - next[a].updated);
        for (const old of keys.slice(62)) delete next[old];
        cache = next;
        if (!shell.fixture) save.restart();
    }
    function refresh() {
        if (!ready) return;
        if (shell.fixture) {
            configured = !!shell.fixtureData.calendarConfigured;
            clocks = shell.fixtureData.clocks || [];
            const fixtureEvents = shell.fixtureData.eventsByDay ? (shell.fixtureData.eventsByDay[selectedKey] || []) : (shell.fixtureData.events || []).filter(e => {
                const start = new Date(e.start), end = new Date(e.end);
                const day = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate());
                const next = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
                return start < next && end > day;
            });
            saveDay(selectedKey, fixtureEvents);
            loading = false; unavailable = false;
        } else if (!reader.running) {
            requestedKey = selectedKey;
            loading = true; unavailable = false;
            reader.running = true;
        }
    }
    function applySnapshot(data) {
        if (data.clocks !== undefined) clocks = data.clocks;
        if (data.configured !== undefined) configured = data.configured;
        if (data.loading !== undefined) loading = data.loading;
        if (data.unavailable !== undefined) unavailable = data.unavailable;
        if (data.events !== undefined) {
            // Replace successful calendars, preserving cached entries from any
            // source that failed this refresh. Never blank the cache mid-fetch.
            const failed = data.failedCalendars || [];
            const old = cache[requestedKey] ? cache[requestedKey].events : [];
            const retained = old.filter(e => failed.includes(e.calendarId));
            if (!data.unavailable || data.events.length || retained.length)
                saveDay(requestedKey, data.events.concat(retained).sort((a,b) => Number(a.allDay !== true) - Number(b.allDay !== true) || a.start - b.start));
        }
    }
    function clockTime(offset) {
        const date = new Date(shell.clock.date.getTime() + offset * 1000);
        return String(date.getUTCHours()).padStart(2, "0") + ":" + String(date.getUTCMinutes()).padStart(2, "0");
    }
    onSelectedKeyChanged: { if (ready) refresh(); }
    FileView { id: saved; path: root.shell.fixture ? "" : root.cachePath; blockLoading: true; atomicWrites: true; printErrors: false }
    Timer { id: save; interval: 200; onTriggered: { if (!cacheDirectory.running) cacheDirectory.running = true; } }
    Process {
        id: cacheDirectory
        command: ["/usr/bin/mkdir", "-p", root.cachePath.slice(0, root.cachePath.lastIndexOf("/"))]
        onExited: (code, status) => {
            if (code === 0) saved.setText(JSON.stringify({version: 1, days: root.cache, clocks: root.clocks, configured: root.configured}));
        }
    }
    Process {
        id: reader
        command: ["/usr/bin/python3", decodeURIComponent(Qt.resolvedUrl("agenda.py").toString().replace(/^file:\/\//, "")), "--date", root.requestedKey]
        stdout: SplitParser {
            onRead: line => {
                try { root.applySnapshot(JSON.parse(line)); }
                catch (error) { console.warn("Invalid agenda status", error); }
            }
        }
        onExited: (code, status) => {
            root.loading = false;
            if (code !== 0) root.unavailable = true;
            if (root.requestedKey !== root.selectedKey) Qt.callLater(root.refresh);
        }
    }
    Connections {
        target: root.shell
        function onPanelChanged() { if (root.shell.panel === "notifications") root.refresh(); }
        function onFixtureDataChanged() { if (root.shell.fixture) root.refresh(); }
    }
    Timer { interval: 300000; repeat: true; running: root.shell.panel === "notifications"; onTriggered: root.refresh() }
    Component.onCompleted: {
        if (!shell.fixture) {
            try {
                const data = JSON.parse(saved.text());
                if (data.version === 1) { cache = data.days || {}; clocks = data.clocks || []; configured = !!data.configured; }
            } catch (e) { /* A fresh cache starts empty. */ }
        }
        ready = true;
        if (shell.fixture) refresh();
    }
}
