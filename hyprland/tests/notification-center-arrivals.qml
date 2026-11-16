import QtQuick
import Quickshell

// Run with a shell fixture on isolated-gui's private nested compositor.
Scope {
    id: test
    property var app
    property var view
    property var originals: ({})
    property var fresh
    property string key: ""
    property string replyingId: ""
    property int phase: 0
    function check(value, message) {
        if (!value) { console.error("CENTER ARRIVALS FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function all(item) {
        let result = [];
        for (const child of item.children || []) result = result.concat([child], all(child));
        return result;
    }
    function cards() { return all(view).filter(item => item.inCenter === true).sort((a, b) => a.index - b.index); }
    function message(id) {
        const callbacks = {};
        const n = {id: id, appName: "Messages", desktopEntry: "messages", appIcon: "", image: "", summary: "Conversation",
            body: "Message " + id, expireTimeout: 0, urgency: 1, transient: false, actions: [], hasInlineReply: true};
        for (const name of ["summary", "body", "appName", "appIcon", "image", "expireTimeout", "urgency", "transient"])
            n[name + "Changed"] = {connect: callback => { callbacks[name] = callback; }};
        n.closed = {connect: callback => { callbacks.closed = callback; }};
        n.dismiss = () => callbacks.closed(2); n.expire = () => callbacks.closed(1);
        return n;
    }
    function arrive(id) {
        app.notifications.receive(message(id));
        const expected = app.notifications.generation + ":" + id;
        check(app.notifications.groups.find(g => g.key === key).entries[0].id === expected,
            "Fresh member was appended behind the stack");
        return expected;
    }
    function stable() {
        check(all(app.pill.activePane).includes(view), "Arrival recreated the group");
        for (const item of cards()) if (originals[item.entry.id])
            check(item === originals[item.entry.id] && item.arrival === 1, "Arrival recreated or reanimated an existing card");
        check(!app.notifications.popups.length && !app.notifications.queuedPopups.length, "Open-center arrival escaped as a banner");
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "A private fixture is required");
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(c.status === Component.Ready, c.errorString()); app = c.createObject(test);
        app.notifications.dnd = true;
        app.notifications.receive(message(1)); app.notifications.receive(message(2));
        key = app.notifications.groups[0].key;
        app.toggle("notifications"); tick.start();
    }
    Timer {
        id: tick; interval: 450
        onTriggered: {
            switch (phase++) {
            case 0:
                view = all(app.pill.activePane).find(item => item.group?.key === key && item.firstCard !== undefined);
                check(!!view && view.geometryReady && !view.expanded, "Collapsed group is not ready");
                for (const item of cards()) originals[item.entry.id] = item;
                arrive(3); interval = 70;
                break;
            case 1:
                fresh = view.firstCard;
                check(fresh.entry.id === app.notifications.generation + ":3" && fresh.index === 0,
                    "Collapsed group did not expose the newest card immediately");
                check(fresh.arrival > 0 && fresh.arrival < 1 && fresh.opacity > 0 && fresh.opacity < 1,
                    "Fresh center member did not drop/fade onto the stack");
                check(fresh.transform[0].y < 0 && fresh.transform[1].angle < 0, "Arrival did not drop with a slight tilt");
                check(cards()[1].opacity === 1 && Math.abs(cards()[1].y + cards()[1].groupOffset) < 1,
                    "Collapsed arrival hid the previous card before landing");
                stable(); interval = 380;
                break;
            case 2:
                check(view.firstCard === fresh && fresh.arrival === 1, "Settling changed the front card");
                app.pill.activePane.toggleGroup(key);
                break;
            case 3:
                check(view.unfold === 1 && cards()[0] === fresh, "Expansion reordered the stack");
                for (const item of cards()) originals[item.entry.id] = item;
                replyingId = cards()[1].entry.id;
                app.notifications.startReply(replyingId, "center"); app.notifications.setDraft(replyingId, "Keep my draft");
                arrive(4); interval = 70;
                break;
            case 4:
                stable();
                check(view.firstCard.entry.id === app.notifications.generation + ":4" && view.firstCard.arrival > 0 && view.firstCard.arrival < 1,
                    "Expanded arrival was deferred or skipped its animation during a reply");
                check(app.notifications.drafts[replyingId] === "Keep my draft", "Arrival lost the reply draft");
                interval = 380;
                break;
            case 5: {
                const before = cards().map(item => item.entry.id).join();
                app.notifications.cancelReply(replyingId);
                check(cards().map(item => item.entry.id).join() === before, "Leaving the reply reordered the group");
                arrive(5); arrive(6); interval = 380;
                break;
            }
            case 6: {
                stable();
                const items = cards();
                check(items.map(item => item.entry.id.split(":").pop()).join() === "6,5,4,3,2,1", "Burst arrivals lost newest-first order");
                for (let i = 1; i < items.length; i++) check(items[i].y >= items[i - 1].y + items[i - 1].height + 9,
                    "Expanded arrival left cards overlapping");
                const n = app.notifications.live[view.firstCard.entry.id];
                n.body = "Updated in place"; app.notifications.receive(n, false);
                check(view.firstCard === items[0] && view.firstCard.arrival === 1, "Content update replayed the entrance");
                app.pill.activePane.toggleGroup(key);
                break;
            }
            case 7:
                check(view.unfold === 0 && view.firstCard.entry.id.endsWith(":6"), "Collapsing changed the front card");
                console.warn("CENTER ARRIVALS PASS: collapsed/expanded drop/fade, immediate newest-first insertion, reply draft, stable delegates, burst arrivals, no delayed sort, updates");
                Qt.quit(); return;
            }
            restart();
        }
    }
    Timer { interval: 8000; running: true; onTriggered: test.check(false, "Timed out"); }
}
