import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Scope {
    id: root
    property string statePath
    property bool dnd: false
    property bool centerOpen: false
    property var entries: []
    property var removing: ({})
    property var removals: ({})
    property var popups: []
    property var queuedPopups: []
    property var popupTimeouts: ({})
    property bool centerHovered: false
    property bool centerOrderPending: false
    property real pausedAt: 0
    readonly property bool bannerFrozen: popups.some(e => !!hovered[e.id] || replying[e.id] === "banner")
    readonly property bool centerFrozen: centerHovered || centerReplyActive
    onCenterFrozenChanged: {
        if (!centerFrozen && centerOrderPending) {
            centerOrderPending = false;
            entries = entries.slice().sort((a,b) => b.time - a.time);
        }
    }
    onCenterOpenChanged: { if (!centerOpen) centerHovered = false; }
    onBannerFrozenChanged: {
        if (bannerFrozen) pausedAt = Date.now();
        else {
            if (pausedAt > 0) {
                const now = Date.now(), elapsed = now - pausedAt;
                const next = Object.assign({}, deadlines);
                for (const id of Object.keys(next)) if (next[id] > 0) next[id] = Math.max(now + 800, next[id] + elapsed);
                deadlines = next;
                pausedAt = 0;
            }
            Qt.callLater(root.flushQueuedPopups);
        }
    }
    property var live: ({})
    property var deadlines: ({})
    property var hovered: ({})
    property var replying: ({})
    property var drafts: ({})
    signal replyFocusRequested(string surface)
    readonly property string generation: Quickshell.env("INVOCATION_ID") || Date.now().toString(36)
    property bool loaded: false
    readonly property int unread: entries.filter(e => !e.read).length
    readonly property bool bannerReplyActive: popups.some(entry => replying[entry.id] === "banner")
    readonly property bool centerReplyActive: Object.values(replying).includes("center")
    readonly property var groups: {
        const appIds = new Map();
        for (const entry of entries)
            if (entry.desktopEntry) appIds.set((entry.app || "Notification").toLowerCase(), entry.desktopEntry);
        const grouped = new Map();
        for (const entry of entries) {
            const name = entry.app || "Notification";
            const key = entry.desktopEntry || appIds.get(name.toLowerCase()) || name.toLowerCase();
            if (!grouped.has(key)) grouped.set(key, {key: key, app: name, icon: entry.icon || "", entries: []});
            grouped.get(key).entries.push(entry);
        }
        return Array.from(grouped.values());
    }
    function persist() { if (loaded) save.restart(); }
    function closePopup(id) {
        queuedPopups = queuedPopups.filter(p => p.id !== id);
        popups = popups.filter(p => p.id !== id);
        const over = Object.assign({}, hovered); delete over[id]; hovered = over;
    }
    function showPopup(entry) {
        if (removing[entry.id]) return;
        if (bannerFrozen) {
            queuedPopups = queuedPopups.filter(p => p.id !== entry.id).concat([entry]).slice(-16);
            return;
        }
        const next = Object.assign({}, deadlines);
        const timeout = popupTimeouts[entry.id] ?? 6000;
        next[entry.id] = timeout === 0 ? 0 : Date.now() + timeout;
        deadlines = next;
        popups = [entry].concat(popups.filter(p => p.id !== entry.id)).slice(0, 4);
    }
    function flushQueuedPopups() {
        if (bannerFrozen || !queuedPopups.length) return;
        const pending = queuedPopups;
        queuedPopups = [];
        for (const entry of pending) showPopup(entry);
    }
    function hidePopup(id) {
        closePopup(id);
        const times = Object.assign({}, deadlines); delete times[id]; deadlines = times;
        const over = Object.assign({}, hovered); delete over[id]; hovered = over;
        // Persistent notifications retain their app actions in the center.
        const n = live[id];
        if (n && n.transient) n.expire();
    }
    function hoverPopup(id, inside) {
        const next = Object.assign({}, hovered);
        if (inside) next[id] = true;
        else delete next[id];
        hovered = next;
    }
    function remove(id) {
        if (removing[id]) return;
        const next = Object.assign({}, removing); next[id] = true; removing = next;
        const deadlines = Object.assign({}, removals); deadlines[id] = Date.now() + 140; removals = deadlines;
    }
    function clear() {
        for (const entry of entries) remove(entry.id);
        for (const entry of popups) remove(entry.id);
        for (const entry of queuedPopups) remove(entry.id);
    }
    function removeGroup(key) {
        const group = groups.find(group => group.key === key);
        if (group) for (const entry of group.entries) remove(entry.id);
    }
    function setDraft(id, text) {
        const next = Object.assign({}, drafts); next[id] = text; drafts = next;
    }
    function startReply(id, surface) {
        const n = live[id];
        if (!n || !n.hasInlineReply) return;
        const next = Object.assign({}, replying); next[id] = surface; replying = next;
        replyFocusRequested(surface);
    }
    function cancelReply(id) {
        const next = Object.assign({}, replying); delete next[id]; replying = next;
        const text = Object.assign({}, drafts); delete text[id]; drafts = text;
    }
    function sendReply(id) {
        const n = live[id];
        const text = drafts[id] || "";
        if (!n || !n.hasInlineReply || !text.trim()) return;
        n.sendInlineReply(text);
        remove(id);
    }
    function markRead() { entries = entries.map(e => Object.assign({}, e, {read: true})); persist(); }
    function invoke(id, action) {
        const n = live[id];
        if (!n) return;
        const a = n.actions.find(a => a.identifier === action);
        if (a) { a.invoke(); remove(id); }
    }
    function receive(n, initial = true) {
        if (initial) n.tracked = true;
        const id = generation + ":" + n.id;
        if (!initial && live[id] !== n) return;
        const alreadyTracked = live[id] === n;
        const pending = Object.assign({}, removals); delete pending[id]; removals = pending;
        const fading = Object.assign({}, removing); delete fading[id]; removing = fading;
        const previous = entries.find(e => e.id === id) || popups.find(e => e.id === id);
        const entry = {id: id, app: String(n.appName || "Notification").slice(0, 200),
            desktopEntry: n.desktopEntry || "", icon: n.appIcon || "", image: n.image || "", summary: String(n.summary).slice(0, 500), body: String(n.body).slice(0, 6000),
            time: previous ? previous.time : Date.now(), read: !initial && previous ? previous.read : centerOpen, critical: n.urgency === 2};
        const next = Object.assign({}, live); next[id] = n; live = next;
        if (!n.transient) {
            if (entries.some(e => e.id === id)) entries = entries.map(e => e.id === id ? entry : e);
            else {
                if (centerFrozen) { entries = entries.concat([entry]).slice(-100); centerOrderPending = true; }
                else entries = [entry].concat(entries).slice(0, 100);
            }
            persist();
        }
        // A content update replaces the existing card in place; it must not
        // remove/reinsert it, restart its appearance, or resurrect a hidden banner.
        const timeout = n.expireTimeout < 0 ? 6000 : n.expireTimeout;
        const durations = Object.assign({}, popupTimeouts);
        const duration = entry.critical ? 0 : timeout;
        const changedDuration = popupTimeouts[id] !== duration;
        durations[id] = duration; popupTimeouts = durations;
        if (popups.some(e => e.id === id)) {
            popups = popups.map(e => e.id === id ? entry : e);
            if (initial || changedDuration) {
                const next = Object.assign({}, deadlines);
                next[id] = duration === 0 ? 0 : Date.now() + duration;
                deadlines = next;
            }
        }
        else if (queuedPopups.some(e => e.id === id)) queuedPopups = queuedPopups.map(e => e.id === id ? entry : e);
        else if (initial && (!dnd || entry.critical)) showPopup(entry);
        // Replacements can reuse the same native object. Register each signal
        // once, otherwise every subsequent update multiplies refresh callbacks.
        if (!initial || alreadyTracked) return;
        function refresh() { root.receive(n, false); }
        function changed() { Qt.callLater(refresh); }
        n.summaryChanged.connect(changed);
        n.bodyChanged.connect(changed);
        n.appNameChanged.connect(changed);
        n.appIconChanged.connect(changed);
        n.imageChanged.connect(changed);
        n.expireTimeoutChanged.connect(changed);
        n.urgencyChanged.connect(changed);
        n.transientChanged.connect(changed);
        n.closed.connect(function(reason) {
            const current = Object.assign({}, root.live);
            // A replacement can reuse this ID before the old object is destroyed.
            if (current[id] === n) {
                delete current[id]; root.live = current; root.closePopup(id);
                const times = Object.assign({}, root.deadlines); delete times[id]; root.deadlines = times;
                const durations = Object.assign({}, root.popupTimeouts); delete durations[id]; root.popupTimeouts = durations;
                root.cancelReply(id);
                const over = Object.assign({}, root.hovered); delete over[id]; root.hovered = over;
                root.entries = root.entries.filter(entry => entry.id !== id);
            }
        });
    }
    onDndChanged: persist()
    onEntriesChanged: {
        const ids = new Set(entries.map(e => e.id));
        for (const id of Object.keys(live)) {
            const n = live[id];
            if (n && !n.transient && !ids.has(id)) n.expire();
        }
    }
    FileView { id: preferences; path: root.statePath; blockLoading: true; atomicWrites: true; printErrors: false }
    Timer {
        id: save; interval: 150
        // Keep preferences only. A saved notification cannot retain the app's
        // live callback, and withdrawn/activated entries must not reappear.
        onTriggered: preferences.setText(JSON.stringify({version: 2, dnd: root.dnd}))
    }
    Timer {
        interval: 250; repeat: true; running: Object.keys(root.deadlines).length > 0
        onTriggered: {
            if (root.bannerFrozen) return;
            const now = Date.now();
            const expired = Object.keys(root.deadlines).filter(id => !root.hovered[id] && !root.replying[id] && root.deadlines[id] > 0 && root.deadlines[id] <= now);
            for (const id of expired) root.hidePopup(id);
        }
    }
    Timer {
        interval: 30; repeat: true; running: Object.keys(root.removals).length > 0
        onTriggered: {
            const due = Object.keys(root.removals).filter(id => root.removals[id] <= Date.now());
            if (!due.length) return;
            for (const id of due) {
                const n = root.live[id];
                if (n) n.dismiss();
                root.closePopup(id);
            }
            root.entries = root.entries.filter(e => !due.includes(e.id));
            const next = Object.assign({}, root.removals);
            for (const id of due) delete next[id];
            root.removals = next;
            removalCleanup.restart();
            root.persist();
        }
    }
    Timer {
        id: removalCleanup; interval: 300
        onTriggered: {
            // Retain fade state until ListView's removal transition finishes.
            const active = new Set(root.entries.concat(root.popups).map(e => e.id));
            const next = {};
            for (const id of Object.keys(root.removing)) if (active.has(id) || root.removals[id]) next[id] = true;
            root.removing = next;
        }
    }
    NotificationServer {
        actionsSupported: true
        inlineReplySupported: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: true
        persistenceSupported: true
        onNotification: n => root.receive(n)
    }
    Component.onCompleted: {
        try {
            const data = JSON.parse(preferences.text());
            if (data.version === 1 || data.version === 2) {
                dnd = !!data.dnd;
            }
        } catch (error) { /* A new or corrupt history starts empty. */ }
        loaded = true;
        persist();
    }
}
