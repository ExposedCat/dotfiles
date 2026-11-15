import QtQuick
import Quickshell

// Exercise group placement in the real retained center on a private compositor.
Scope {
    id: test
    property var app: null
    property int phase: 0
    function check(value, message) {
        if (!value) { console.error("CENTER LAYOUT FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function all(item) {
        let result = [];
        for (const child of item.children || []) result = result.concat([child], all(child));
        return result;
    }
    function arrive(id, group, length) {
        const entry = {id: "spacing:" + id, app: "Messages", summary: "Conversation " + group,
            body: "A message with variable wrapping and height. ".repeat(length), time: Date.now(), read: false};
        app.notifications.entries = [entry].concat(app.notifications.entries);
    }
    function separated() {
        const list = all(app.pill.activePane).find(item => item.objectName === "notificationList");
        check(!!list && list.count === app.notifications.groups.length, "Missing center groups");
        check(!!list.itemAtIndex(0) && !!list.itemAtIndex(1), "Need neighboring groups to check placement");
        let previous = null;
        for (let i = 0; i < list.count; i++) {
            const group = list.itemAtIndex(i);
            if (!group) continue;
            check(group.height > 0, "Group has no height");
            check(group.opacity === 1, "Arrival fade did not finish");
            if (previous) check(Math.abs(group.y - previous.y - previous.height - list.spacing) < 1,
                "Groups overlap or leave excess space at index " + i);
            previous = group;
        }
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "Private fixture required");
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(c.status === Component.Ready, c.errorString()); app = c.createObject(test);
        app.notifications.dnd = true;
        for (let i = 0; i < 6; i++) arrive(i, i % 4, i % 3 * 4 + 1);
        app.toggle("notifications");
    }
    Timer {
        interval: 450; repeat: true; running: !!test.app
        onTriggered: {
            switch (test.phase++) {
            case 0:
                test.separated(); test.app.toggle("notifications"); break;
            case 1:
                for (let i = 6; i < 12; i++) test.arrive(i, i % 4, i % 3 * 4 + 1);
                break;
            case 2:
                test.app.toggle("notifications"); break;
            case 3:
                test.separated(); test.app.toggle("power"); break;
            case 4:
                for (let i = 12; i < 18; i++) test.arrive(i, i % 4, i % 3 * 4 + 1);
                break;
            case 5:
                test.app.toggle("notifications"); break;
            case 6:
                test.separated(); test.app.pill.paneWidth = 900; break;
            case 7:
                test.separated();
                for (let i = 18; i < 22; i++) test.arrive(i, i % 4, i % 3 * 4 + 1);
                test.arrive(22, 4, 1);
                break;
            case 8:
                test.separated();
                test.app.notifications.entries = test.app.notifications.entries.map(entry =>
                    Object.assign({}, entry, {body: "Shortened message"}));
                break;
            case 9:
                test.separated();
                test.app.notifications.remove(test.app.notifications.entries[0].id);
                break;
            case 10:
                test.separated();
                console.warn("CENTER LAYOUT PASS: first open, hidden/live arrivals, retained view resize, width reflow, shrinking bodies, dismissal");
                Qt.quit();
            }
        }
    }
    Timer { interval: 9000; running: true; onTriggered: test.check(false, "Timed out"); }
}
