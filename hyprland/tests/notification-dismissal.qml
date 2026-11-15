import QtQuick
import Quickshell

// Run the real center under an isolated nested Wayland compositor.
Scope {
    id: test
    property var app: null
    property var groupView
    property var otherGroup
    property var originals: ({})
    property var leaving
    property real exitHeight: 0
    property real otherY: 0
    property string key: ""
    property string otherKey: ""
    property string leavingId: ""
    property int phase: 0
    function check(value, message) {
        if (!value) { console.error("DISMISSAL FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function all(item) {
        let result = [];
        for (const child of item.children || []) result = result.concat([child], all(child));
        return result;
    }
    function group(key) { return all(app.pill.activePane).find(item => item.group?.key === key && item.firstCard !== undefined); }
    function cards(view) { return all(view).filter(item => item.inCenter === true); }
    function card(id) { return cards(groupView).find(item => item.entry.id === id); }
    function message(id, title = "Conversation") {
        const callbacks = {};
        const n = {id: id, appName: "Messages", desktopEntry: "messages", appIcon: "", image: "", summary: title,
            body: "Message " + id + ": keep this card and its group stable.", expireTimeout: 0, urgency: 1,
            transient: false, actions: [], hasInlineReply: false};
        for (const name of ["summary", "body", "appName", "appIcon", "image", "expireTimeout", "urgency", "transient"])
            n[name + "Changed"] = {connect: callback => { callbacks[name] = callback; }};
        n.closed = {connect: callback => { callbacks.closed = callback; }};
        n.dismiss = () => callbacks.closed(2); n.expire = () => callbacks.closed(1);
        return n;
    }
    function stable() {
        check(group(key) === groupView, "Dismissing one member recreated its group");
        check(group(otherKey) === otherGroup, "Dismissing a member recreated another group");
        for (const item of cards(groupView))
            if (originals[item.entry.id]) check(item === originals[item.entry.id], "A surviving card was recreated");
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "A private fixture is required");
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(c.status === Component.Ready, c.errorString()); app = c.createObject(test);
        app.notifications.dnd = true;
        app.notifications.receive(message(4, "Other conversation")); app.notifications.receive(message(5, "Other conversation"));
        otherKey = app.notifications.groups[0].key;
        for (let i = 1; i <= 3; i++) app.notifications.receive(message(i));
        key = app.notifications.groups[0].key;
        app.toggle("notifications"); app.pill.activePane.toggleGroup(key);
        tick.start();
    }
    Timer {
        id: tick; interval: 400
        onTriggered: {
            switch (phase++) {
            case 0:
                groupView = group(key); otherGroup = group(otherKey);
                check(!!groupView && !!otherGroup && groupView.unfold === 1, "Expanded groups were not created");
                for (const item of cards(groupView)) originals[item.entry.id] = item;
                leaving = groupView.firstCard; leavingId = leaving.entry.id; exitHeight = leaving.height;
                app.notifications.remove(leavingId); interval = 70;
                break;
            case 1:
                stable();
                check(card(leavingId) === leaving && leaving.height === exitHeight, "Exit collapsed or destroyed the card before its slide/fade");
                check(leaving.dismissProgress > 0 && leaving.dismissProgress < 1 && leaving.opacity > 0 && leaving.opacity < 1,
                    "Dismissed card did not slide and fade upward");
                check(groupView.expanded && groupView.unfold === 1, "Single dismissal collapsed the expanded group");
                interval = 190;
                break;
            case 2:
                stable();
                check(!app.notifications.entries.some(e => e.id === leavingId) && card(leavingId) === leaving,
                    "Native dismissal destroyed the card before its presentation finished");
                check(leaving.opacity === 0 && leaving.height > 0 && leaving.height < exitHeight, "Space did not collapse after the upward fade");
                interval = 200;
                break;
            case 3:
                stable(); check(!card(leavingId) && cards(groupView).length === 2, "Finished exit leaked a card");
                app.pill.activePane.toggleGroup(key); interval = 330;
                break;
            case 4:
                check(groupView.unfold === 0, "Group failed to collapse");
                leaving = groupView.firstCard; leavingId = leaving.entry.id;
                app.notifications.remove(leavingId); interval = 80;
                break;
            case 5:
                stable();
                check(groupView.firstCard !== leaving && groupView.firstCard.opacity === 1 && groupView.firstCard.groupReveal === 1,
                    "Collapsed stack failed to reveal the surviving card underneath the exit");
                check(groupView.height >= groupView.firstCard.height && groupView.height > 0, "Collapsed group shrank away and reappeared");
                interval = 400;
                break;
            case 6:
                stable(); check(!card(leavingId) && cards(groupView).length === 1, "Collapsed dismissal leaked a card");
                leaving = groupView.firstCard; leavingId = leaving.entry.id; otherY = otherGroup.y;
                app.notifications.remove(leavingId); interval = 80;
                break;
            case 7:
                stable(); check(leaving.opacity > 0 && leaving.opacity < 1 && groupView.height > 0, "Last member skipped its upward exit");
                interval = 100;
                break;
            case 8:
                stable(); check(otherGroup.y === otherY, "Last-member dismissal reordered the retiring group before its exit finished");
                interval = 320;
                break;
            case 9:
                check(!group(key) && group(otherKey) === otherGroup, "Last-member retirement leaked or recreated a group");
                check(app.notifications.entries.length === 2 && cards(otherGroup).length === 2, "Single dismissal affected another group");
                console.warn("DISMISSAL PASS: upward fade, retained pixels/layout, delayed reflow, stable group/card identities, collapsed successor reveal, last-member retirement");
                Qt.quit(); return;
            }
            restart();
        }
    }
    Timer { interval: 8000; running: true; onTriggered: test.check(false, "Timed out"); }
}
