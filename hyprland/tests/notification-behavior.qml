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
    property var third
    function message(id, app) {
        const signals = {};
        const n = {connections: 0, id: id, tracked: false, appName: app || "Test", desktopEntry: app || "test", appIcon: "", image: "", summary: "Message", body: "Body", expireTimeout: 50, urgency: 1, transient: false};
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
            test.check(store.deadlines[test.firstId] >= Date.now() + 700, "Hover did not pause expiry");

            store.dnd = true;
            store.centerHovered = true;
            store.receive(third);
            test.check(store.entries[0].id === test.secondId, "Center notifications rearranged under the pointer");
            release.start();
        }
    }
    Timer {
        id: release; interval: 10
        onTriggered: {
            test.check(store.popups.length === 2 && store.queuedPopups.length === 0, "Queued arrival did not appear after leaving");
            store.hidePopup(test.secondId);
            second.setBody("An update must not resurrect a hidden banner");
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
            console.warn("NOTIFICATION REGRESSION PASS: hover expiry, queued arrivals, stable updates, hidden banners, center ordering, dismissal");
            Qt.quit();
        }
    }
}
