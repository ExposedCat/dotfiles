import QtQuick
import Quickshell

// Run through isolated-gui on its own private bus. Set DOTFILES_SHELL_SOURCE
// to the absolute config/shell directory; XDG_STATE_HOME must be test-local.
Scope {
    id: test
    property string firstId: ""
    property string secondId: ""
    function check(condition, message) { if (!condition) { console.error("NOTIFICATION REGRESSION FAIL:", message); Qt.exit(1); throw Error(message); } }
    property var store
    property var first
    property var second
    property var fourth
    property var critical
    property string transientId: ""
    property var third
    function message(id, app) {
        const signals = {};
        const n = {connections: 0, id: id, tracked: false, appName: app || "Test", desktopEntry: app || "test", appIcon: "", image: "", summary: "Message", body: "Body", expireTimeout: 50, urgency: 1, transient: false, actions: [], hasInlineReply: false};
        for (const name of ["summary", "body", "appName", "appIcon", "image", "expireTimeout", "urgency", "transient"]) {
            n[name + "Changed"] = {connect: handler => { signals[name] = handler; n.connections++; }};
        }
        n.closed = {connect: handler => { signals.closed = handler; n.connections++; }};
        n.expire = () => { if (signals.closed) signals.closed(1); };
        n.dismiss = () => { if (signals.closed) signals.closed(2); };
        n.setSummary = text => { n.summary = text; if (signals.summary) signals.summary(); };
        n.setBody = text => { n.body = text; if (signals.body) signals.body(); };
        return n;
    }
    Component.onCompleted: {
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/Notifications.qml");
        check(component.status === Component.Ready, component.errorString());
        store = component.createObject(test, {statePath: Quickshell.env("XDG_STATE_HOME") + "/notification-regression.json"});
        check(!!store, "Could not create notification store");
        first = message(1); second = message(2); third = message(3, "Third");
        store.dnd = false;
        store.receive(first);
        firstId = store.entries[0].id;
        store.hoverPopup(firstId, true);
        store.receive(second);
        secondId = store.entries.find(e => e.id !== firstId).id;
        check(store.popups.length === 1 && store.popups[0].id === firstId, "Arrival moved the hovered banner");
        check(store.queuedPopups.length === 1, "Arrival was not queued during hover");
        store.receive(first);
        check(first.connections === 9, "Replacement duplicated native signal subscriptions");
        check(store.popups.length === 1 && store.popups[0].id === firstId, "Replacement moved the hovered banner");
        first.setSummary("Updated without removing the card");
    }
    Timer {
        interval: 350; running: true
        onTriggered: {
            test.check(store.popups.length === 1 && store.popups[0].id === test.firstId, "Timeout or content update removed the hovered banner");
            test.check(store.popups[0].summary === first.summary, "Visible banner did not update in place");
            store.hoverPopup(test.firstId, false);
            test.check(!store.popups.some(e => e.id === test.firstId) && store.entries.some(e => e.id === test.firstId) && store.live[test.firstId], "Leaving a hovered banner must retain it only in the center");
            test.check(store.deadlines[test.firstId] === undefined, "Consumed banner retained an expiry timer");

            store.dnd = true;
            release.start();
        }
    }
    Timer {
        id: release; interval: 10
        onTriggered: {
            test.check(store.popups.length === 1 && store.popups[0].id === test.secondId && store.queuedPopups.length === 0, "Queued arrival did not appear after leaving");
            store.hidePopup(test.secondId);
            second.setBody("An update must not resurrect a hidden banner");
            store.centerOpen = true;
            store.receive(third);
            test.check(store.entries[0].id === store.generation + ":3", "Open-center arrival was not inserted newest first");
            store.centerOpen = false;
            followup.start();
        }
    }
    Timer {
        id: followup; interval: 40
        onTriggered: {
            test.check(!store.popups.some(e => e.id === test.secondId), "An update resurrected a hidden banner");
            store.remove(test.firstId);
            test.check(store.removing[test.firstId], "Dismissal skipped the fade state");
            finish.start();
        }
    }
    Timer {
        id: finish; interval: 220
        onTriggered: {
            test.check(!store.entries.some(e => e.id === test.firstId), "Animated dismissal did not finish");
            store.dnd = false;
            fourth = message(4); fourth.expireTimeout = 0; store.receive(fourth);
            test.check(store.popups.length === 1, "Fresh notifications stopped presenting");
            store.centerOpen = true;
            test.check(store.popups.length === 0 && store.queuedPopups.length === 0, "Opening the center did not consume banners");
            critical = message(5); critical.urgency = 2; critical.expireTimeout = 0; store.receive(critical);
            const transient = message(6); transient.transient = true; store.receive(transient);
            test.transientId = store.generation + ":6";
            test.check(store.popups.length === 0 && store.queuedPopups.length === 0, "Center arrivals queued banners, including a critical notification");
            centerFinish.start();
        }
    }
    Timer {
        id: centerFinish; interval: 50
        onTriggered: {
            test.check(!store.live[test.transientId], "Suppressed transient did not expire");
            store.centerOpen = false;
            store.receive(critical); critical.setBody("A replacement stays in the center");
            test.check(store.popups.length === 0 && store.queuedPopups.length === 0, "Closing the center replayed notifications");
            const fresh = message(7); fresh.expireTimeout = 0; fresh.hasInlineReply = true; store.receive(fresh);
            const id = store.generation + ":7";
            test.check(store.popups.length === 1, "A genuinely new arrival did not present after closing");
            store.startReply(id, "banner"); store.setDraft(id, "A draft");
            store.receive(message(8));
            test.check(store.queuedPopups.length === 1, "Reply did not queue the next arrival");
            store.centerOpen = true;
            test.check(store.replying[id] === "center" && store.drafts[id] === "A draft", "Opening the center discarded an active reply");
            store.cancelReply(id); store.centerOpen = false;
            settled.start();
        }
    }
    Timer {
        id: settled; interval: 50
        onTriggered: {
            test.check(store.popups.length === 0 && store.queuedPopups.length === 0, "A queued banner escaped after closing the center");
            console.warn("NOTIFICATION REGRESSION PASS: hover consumption, stable updates, center-only arrivals, no replay, transient cleanup, reply transfer, dismissal");
            Qt.quit();
        }
    }

}
