import QtQuick
import Quickshell

// Private-display regression for the center's compact group controls.
Scope {
    id: test
    property var store: null
    property var groupView
    property string key: ""
    property string clickedId: ""
    property var closeButton
    property int phase: 0
    function check(value, message) {
        if (!value) { console.error("CENTER CONTROLS FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function component(name) {
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/" + name + ".qml");
        check(c.status === Component.Ready, c.errorString()); return c;
    }
    function all(item) {
        let result = [];
        for (const child of item.children || []) result = result.concat([child], all(child));
        return result;
    }
    function named(item, name) { return all(item).find(child => child.objectName === name); }
    function message(id, title = "Conversation", app = "Messages") {
        const callbacks = {};
        const n = {id: id, appName: app, desktopEntry: app.toLowerCase(), appIcon: "", image: "", summary: title,
            body: "A message with its own dismiss action.", expireTimeout: 0, urgency: 1, transient: false, actions: [], hasInlineReply: false};
        for (const name of ["summary", "body", "appName", "appIcon", "image", "expireTimeout", "urgency", "transient"])
            n[name + "Changed"] = {connect: callback => { callbacks[name] = callback; }};
        n.closed = {connect: callback => { callbacks.closed = callback; }};
        n.dismiss = () => callbacks.closed(2); n.expire = () => callbacks.closed(1);
        return n;
    }
    function members() { return store.entries.filter(entry => store.popupKey(entry) === key); }
    FloatingWindow {
        id: window
        title: "Notification center controls test"
        implicitWidth: 680; implicitHeight: 850
        visible: true; color: "#302723"
    }
    Component.onCompleted: {
        store = component("Notifications").createObject(test, {statePath: Quickshell.env("XDG_STATE_HOME") + "/center-controls.json"});
        store.dnd = true;
        for (let i = 1; i <= 3; i++) store.receive(message(i));
        key = store.popupKey(store.entries[0]);
        store.receive(message(4, "Other title")); store.receive(message(5, "Conversation", "Mail"));
        check(store.groups.length === 3, "Center must group by both app and title");
        const theme = component("PillTheme").createObject(test);
        groupView = component("NotificationGroup").createObject(window.contentItem,
            {theme: theme, store: store, group: store.groups.find(g => g.key === key), width: 620, x: 30, y: 30});
        groupView.toggleExpanded.connect(() => { groupView.expanded = !groupView.expanded; });
        tick.start();
    }
    Connections {
        target: test.store
        function onGroupsChanged() {
            if (!test.groupView) return;
            const group = test.store.groups.find(g => g.key === test.key);
            if (group) test.groupView.group = group;
            else test.groupView.visible = false;
        }
    }
    Timer {
        id: tick; interval: 300
        onTriggered: {
            switch (phase++) {
            case 0: {
                const card = groupView.firstCard;
                check(card.y === 0 && card.groupControls && card.groupCount === 3, "Center kept an app header or lost the first-card controls");
                const toggle = named(card, "notificationGroupToggle"); closeButton = named(card, "notificationDismiss");
                check(toggle.visible && closeButton.grouped && toggle.x + toggle.width <= closeButton.x, "Chevron must sit immediately left of the first cross");
                check(!all(card).some(child => child.count === 3 && child.visible), "Center kept the group count badge");
                toggle.clicked(Qt.LeftButton);
                break;
            }
            case 1: {
                check(groupView.unfold === 1, "In-card chevron failed to expand the group");
                const bottom = named(groupView, "notificationGroupCollapse");
                const cards = all(groupView).filter(child => child.inCenter === true);
                check(bottom.visible && bottom.y >= Math.max(...cards.map(card => card.y + card.height)), "Bottom collapse control must remain on a separate line");
                clickedId = groupView.firstCard.entry.id;
                closeButton.beginHold(); interval = 130;
                break;
            }
            case 2:
                check(closeButton.progress > 0 && closeButton.progress < 1, "Holding the cross did not animate circular progress");
                closeButton.releaseHold(); interval = 230;
                break;
            case 3:
                check(members().length === 2 && !store.entries.some(e => e.id === clickedId), "Short click must remove only its own notification");
                check(store.entries.length === 4, "Short click removed other groups");
                closeButton = named(groupView.firstCard, "notificationDismiss");
                closeButton.beginHold(); interval = 100;
                break;
            case 4:
                closeButton.cancelHold(); interval = 650;
                break;
            case 5:
                check(members().length === 2 && closeButton.progress === 0, "Canceled hold dismissed a group or left progress visible");
                closeButton.beginHold(); interval = 750;
                break;
            case 6:
                check(members().length === 0 && store.entries.length === 2, "Completed hold must remove only its app/title group");
                check(store.entries.some(e => e.summary === "Other title") && store.entries.some(e => e.app === "Mail"), "Group hold removed another title or app");
                console.warn("CENTER CONTROLS PASS: app/title groups, no headers/counts, first-card chevron, bottom collapse row, single dismiss, hold progress, cancellation, group-only hold dismiss");
                Qt.quit(); return;
            }
            restart();
        }
    }
    Timer { interval: 6000; running: true; onTriggered: test.check(false, "Timed out"); }
}
