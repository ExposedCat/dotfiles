import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    required property var shell
    readonly property int monthCount: 12
    property date rangeStart: new Date(shell.clock.date.getFullYear(), 0, 1)
    property date selectedDate: shell.clock.date
    readonly property date nextDate: dayAfter(selectedDate)
    property var requestedRange: null
    property var cache: ({})
    property var clocks: []
    property bool configured: false
    property bool loading: false
    property bool unavailable: false
    property bool ready: false
    readonly property int refreshInterval: 300000
    readonly property int cachedMonthLimit: 2 * (monthCount + 1) + 1
    readonly property string cachePath: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/dotfiles/hyprland/agenda.json"
    function dayKey(date) { return Qt.formatDateTime(date, "yyyy-MM-dd"); }
    function monthKey(date) { return Qt.formatDateTime(date, "yyyy-MM"); }
    function dayAfter(date) { return new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1); }
    function monthOffset(date, offset) { return new Date(date.getFullYear(), date.getMonth() + offset, 1); }
    function eventsOn(key) { return cache[key]?.events ?? []; }
    function selectDate(date) { selectedDate = date; }
    function rangeIsFresh(first, until) {
        const cutoff = Date.now() - refreshInterval;
        for (let day = first; day < until; day = dayAfter(day)) {
            const entry = cache[dayKey(day)];
            if (!entry?.complete || !(entry.fetchedAt >= cutoff)) return false;
        }
        return true;
    }
    function refresh(force) {
        if (!ready || reader.running) return;
        const first = rangeStart;
        // Include the following day even when the last visible date is selected.
        const until = dayAfter(monthOffset(first, monthCount));
        if (!shell.fixture && !force && rangeIsFresh(first, until)) {
            unavailable = false;
            return;
        }
        requestedRange = {first: first, until: until};
        if (shell.fixture) {
            configured = !!shell.fixtureData.calendarConfigured;
            clocks = shell.fixtureData.clocks || [];
            const {events, eventsByDay} = shell.fixtureData;
            saveRange(eventsByDay ? [] : events || [], [], eventsByDay);
        } else {
            loading = true; unavailable = false;
            reader.command = [shell.helper, "agenda", "--range", dayKey(first), dayKey(until)];
            reader.running = true;
        }
    }
    function saveRange(events, failed, eventsByDay) {
        const {first, until} = requestedRange;
        const fetchedAt = Date.now();
        const days = {};
        for (let day = first; day < until; day = dayAfter(day)) {
            const key = dayKey(day);
            // Keep cached instances from sources that could not be reached.
            const entries = eventsOn(key).filter(event => failed.includes(event.calendarId));
            days[key] = {events: entries.concat(eventsByDay?.[key] || []), fetchedAt: fetchedAt, complete: failed.length === 0};
        }
        for (const event of events) {
            const start = new Date(event.start).getTime();
            const end = new Date(event.end).getTime();
            const begin = Math.max(start, first.getTime());
            const stop = Math.min(Math.max(end, start + 1), until.getTime());
            if (!(begin < stop)) continue;
            const date = new Date(begin);
            for (let day = new Date(date.getFullYear(), date.getMonth(), date.getDate()); day < stop; day = dayAfter(day))
                days[dayKey(day)]?.events.push(event);
        }
        for (const day of Object.values(days))
            day.events.sort((a, b) => Number(b.allDay === true) - Number(a.allDay === true) || new Date(a.start) - new Date(b.start));
        const next = Object.assign({}, cache, days);
        pruneCache(next, first);
        cache = next;
        if (!shell.fixture) save.restart();
    }
    function pruneCache(days, fetchedStart) {
        const recency = {};
        for (const [key, day] of Object.entries(days)) {
            const month = key.slice(0, 7);
            recency[month] = Math.max(recency[month] ?? 0, day.fetchedAt ?? 0);
        }
        const storedMonths = Object.keys(recency);
        if (storedMonths.length <= cachedMonthLimit) return;

        // Protect today, the displayed range, and the fetch that just finished.
        const keep = new Set([monthKey(shell.clock.date)]);
        for (const start of [rangeStart, fetchedStart]) {
            for (let offset = 0; offset <= monthCount; offset++) {
                const month = monthKey(monthOffset(start, offset));
                if (recency[month] !== undefined) keep.add(month);
            }
        }
        storedMonths.sort((a, b) => recency[b] - recency[a]);
        for (const month of storedMonths) {
            if (keep.size >= cachedMonthLimit) break;
            keep.add(month);
        }
        for (const key of Object.keys(days)) {
            if (!keep.has(key.slice(0, 7))) delete days[key];
        }
    }
    function applySnapshot(data) {
        if (data.clocks !== undefined) clocks = data.clocks;
        if (data.configured !== undefined) configured = data.configured;
        if (data.loading !== undefined) loading = data.loading;
        if (data.unavailable !== undefined) unavailable = data.unavailable;
        if (data.events !== undefined) saveRange(data.events, data.failedCalendars || []);
    }
    function clockTime(offset) {
        const date = new Date(shell.clock.date.getTime() + offset * 1000);
        return String(date.getUTCHours()).padStart(2, "0") + ":" + String(date.getUTCMinutes()).padStart(2, "0");
    }
    onRangeStartChanged: {
        const monthAfter = monthOffset(rangeStart, monthCount);
        if (selectedDate < rangeStart) selectDate(rangeStart);
        else if (selectedDate >= monthAfter)
            selectDate(new Date(monthAfter.getFullYear(), monthAfter.getMonth(), 0));
        if (shell.panel === "calendar") refresh();
    }
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
        stdout: SplitParser {
            onRead: line => {
                try { root.applySnapshot(JSON.parse(line)); }
                catch (error) { console.warn("Invalid agenda status", error); }
            }
        }
        onExited: (code, status) => {
            root.loading = false;
            if (code !== 0) root.unavailable = true;
            if (root.shell.panel === "calendar" && root.dayKey(root.requestedRange.first) !== root.dayKey(root.rangeStart)) Qt.callLater(root.refresh);
        }
    }
    Connections {
        target: root.shell
        function onPanelChanged() { if (root.shell.panel === "calendar") root.refresh(); }
        function onFixtureDataChanged() { if (root.shell.fixture) root.refresh(); }
    }
    Timer { interval: root.refreshInterval; repeat: true; running: root.shell.panel === "calendar"; onTriggered: root.refresh(true) }
    Component.onCompleted: {
        if (!shell.fixture) {
            try {
                const data = JSON.parse(saved.text());
                if (data.version === 1) { cache = data.days || {}; clocks = data.clocks || []; configured = !!data.configured; }
            } catch (e) { /* A fresh cache starts empty. */ }
        }
        ready = true;
        if (shell.fixture || shell.panel === "calendar") refresh();
    }
}
