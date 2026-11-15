import QtQuick
import Quickshell

// Run on isolated-gui's private display and bus with test-local state.
Scope {
    id: test
    property var store
    property var banners
    property var original
    property var first
    property var second
    property int phase: 0
    property string key: ""
    property string firstId: ""
    property string secondId: ""
    property string otherTitleId: ""
    function check(value, message) {
        if (!value) { console.error("BANNER GROUPING FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function component(name) {
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/" + name + ".qml");
        check(c.status === Component.Ready, c.errorString());
        return c;
    }
    function descendants(item) {
        let result = [];
        for (const child of (item.children || [])) result = result.concat([child], descendants(child));
        return result;
    }
    function surfaces() { return descendants(banners).filter(item => item.objectName.startsWith("banner:")); }
    function surface(groupKey) { return surfaces().find(item => item.group.key === groupKey && item.presented); }
    function message(id, title = "Project chat", app = "Messages") {
        const callbacks = {};
        const n = {id: id, appName: app, desktopEntry: app.toLowerCase(), appIcon: "", image: "", summary: title,
            body: "Message " + id + ": The latest update is ready to review.", expireTimeout: 0, urgency: 1,
            transient: false, actions: [], hasInlineReply: true};
        n.actions = [{identifier: "default", text: "Open", invoke: () => { n.activated = true; }}];
        for (const name of ["summary", "body", "appName", "appIcon", "image", "expireTimeout", "urgency", "transient"])
            n[name + "Changed"] = {connect: callback => { callbacks[name] = callback; }};
        n.closed = {connect: callback => { callbacks.closed = callback; }};
        n.expire = () => { if (callbacks.closed) callbacks.closed(1); };
        n.dismiss = () => { if (callbacks.closed) callbacks.closed(2); };
        n.sendInlineReply = text => { n.reply = text; };
        n.update = title => { n.summary = title; if (callbacks.summary) callbacks.summary(); };
        return n;
    }
    function receive(n) { store.receive(n); return store.generation + ":" + n.id; }
    FloatingWindow {
        id: window
        title: "Notification banner grouping test"
        implicitWidth: 900; implicitHeight: 950
        color: "#292929"
        visible: true
        mask: Region { regions: test.banners ? test.banners.inputRegions : [] }
    }
    Component.onCompleted: {
        store = component("Notifications").createObject(test, {statePath: Quickshell.env("XDG_STATE_HOME") + "/grouping-test.json"});
        store.dnd = false;
        const theme = component("ShellTheme").createObject(test);
        banners = component("NotificationBanners").createObject(window.contentItem,
            {theme: theme, store: store, width: 454, x: 446, y: theme.panelGap});
        first = message(1); firstId = receive(first);
        key = store.popupKey(store.popups[0]);
        tick.start();
    }
    Timer {
        id: tick; interval: 380
        onTriggered: {
            switch (phase++) {
            case 0:
                original = surface(key);
                otherTitleId = receive(message(3, "Another conversation"));
                receive(message(4, "Project chat", "Mail"));
                second = message(2); secondId = receive(second); memberProbe.start();
                break;
            case 1: {
                check(store.popupGroups.length === 3 && banners.presentationCount === 3, "App and title must both match to share a banner");
                check(store.groups.length === 3, "Center groups must also match app and title");
                const group = surface(key);
                check(group === original && group.offset === 0 && group.entry.id === secondId && group.arrival === 1, "New member recreated or reanimated the whole group");
                check(group.firstCard.groupCount === 2 && group.stackCount === 1, "Collapsed group lost its count or stack preview");
                check(group.height === group.collapsedHeight, "Collapsed stack has the wrong height");
                const preview = Quickshell.env("DOTFILES_BANNER_PREVIEW");
                if (preview) {
                    group.expanded = preview === "expanded";
                    console.warn("BANNER GROUP PREVIEW READY");
                    return;
                }
                group.firstCard.toggleGroup();
                break;
            }
            case 2: {
                const group = surface(key);
                check(group.expanded && group.unfold === 1, "Group did not expand");
                const cards = descendants(group).filter(item => item.objectName === "notification-banner-card");
                check(cards.length === 2 && cards.every(card => card.enabled && card.opacity === 1), "Expanded members are not interactive");
                check(cards[1].y >= cards[0].y + cards[0].height + 9, "Expanded cards overlap");
                check(group.height >= cards[0].height + cards[1].height + 9, "Expanded group clips its messages");
                const next = surfaces().filter(item => item.presented && item.y > group.y).sort((a, b) => a.y - b.y)[0];
                check(next.y >= group.y + group.height + 13, "Expanded group overlaps its neighbor");
                store.startReply(secondId, "banner"); store.setDraft(secondId, "On my way");
                receive(message(5));
                check(store.queuedPopups.length === 1, "Reply failed to freeze grouped arrivals");
                store.sendReply(secondId);
                check(second.reply === "On my way", "Reply targeted the wrong group member");
                break;
            }
            case 3:
                check(!store.entries.some(e => e.id === secondId), "Replied member was not removed");
                check(store.queuedPopups.length === 0 && surface(key).group.entries.length === 2, "Queued member did not join the existing group");
                first.update("A new title");
                break;
            case 4:
                check(store.popupGroups.length === 4 && banners.presentationCount === 4, "Title replacement failed to split the stack");
                check(new Set(surfaces().map(item => item.objectName)).size === surfaces().length, "Splitting duplicated a surface ID");
                first.update("Project chat");
                break;
            case 5:
                check(store.popupGroups.length === 3 && banners.presentationCount === 3, "Title replacement failed to merge groups");
                check(surface(key).group.entries.length === 2, "Merged group lost a member");
                // More members must not consume slots reserved for other groups.
                receive(message(6)); receive(message(7)); receive(message(8));
                break;
            case 6:
                check(store.popups.length === 7 && store.popupGroups.length === 3, "Banner limit counted members instead of groups");
                check(surface(key).firstCard.groupCount === 5, "Group count did not include every message");
                store.hoverPopupGroup(key, true);
                receive(message(9, "Queued conversation"));
                check(store.queuedPopups.length === 1 && store.bannerFrozen, "Hovering a stack did not freeze arrivals");
                store.hoverPopupGroup(key, false);
                break;
            case 7:
                check(!store.popups.some(e => store.popupKey(e) === key), "Leaving a group failed to consume all its members");
                check(store.entries.filter(e => store.popupKey(e) === key).length === 5, "Hover consumption deleted center entries");
                check(store.queuedPopups.length === 0 && store.popupGroups.length === 3, "Hover consumption failed to release the queue");
                receive(message(10)); receive(message(11));
                break;
            case 8:
                surface(key).firstCard.dismissGroup();
                break;
            case 9:
                check(!store.entries.some(e => [store.generation + ":10", store.generation + ":11"].includes(e.id)), "Group dismissal left matching members active");
                check(store.entries.some(e => e.id === otherTitleId) && store.entries.some(e => e.id === firstId), "Banner dismissal removed another title or center-only history");
                receive(message(12, "Fourth conversation"));
                receive(message(13, "Fifth conversation"));
                break;
            case 10:
                check(store.popupGroups.length === 4 && banners.presentationCount === 4, "The four-group limit was not preserved");
                store.centerOpen = true;
                break;
            case 11:
                check(banners.presentationCount === 0 && banners.inputRegions.length === 0, "Opening the center leaked grouped banners or input regions");
                store.centerOpen = false;
                break;
            case 12:
                check(store.popups.length === 0 && store.queuedPopups.length === 0, "Closing the center replayed a group");
                const expiring = message(14, "Expiring group"); expiring.expireTimeout = 100;
                receive(expiring);
                const member = message(15, "Expiring group"); member.expireTimeout = 100;
                receive(member);
                interval = 600;
                break;
            case 13:
                check(banners.presentationCount === 0 && store.entries.some(e => e.id === store.generation + ":14"), "Group expiry leaked a banner or removed history");
                store.singlePopup = true;
                receive(message(16, "Single stack")); receive(message(17, "Single stack"));
                receive(message(18, "Next stack"));
                check(store.popups.length === 2 && store.popupGroups.length === 1 && store.queuedPopups.length === 1, "Single-popup mode must count groups");
                store.startReply(store.generation + ":16", "banner");
                receive(message(19, "Single stack"));
                store.cancelReply(store.generation + ":16");
                interval = 300;
                break;
            case 14:
                check(store.popups.length === 3 && store.queuedPopups.length === 1, "Single-popup mode failed to flush matching queued members");
                for (const entry of store.popups) store.dismissBanner(entry.id);
                break;
            case 15:
                check(store.popups.length === 1 && store.popups[0].summary === "Next stack" && store.queuedPopups.length === 0, "Single-popup mode failed to advance to the next group");
                console.warn("BANNER GROUPING PASS: app/title matching, stable stack, expand, reply, split/merge, capacity, hover queue, group dismissal, center consumption, expiry, single-group queue");
                Qt.quit(); return;
            }
            restart();
        }
    }
    Timer {
        id: memberProbe; interval: 70
        onTriggered: {
            const group = test.surface(test.key), card = group.firstCard;
            test.check(group.arrival === 1 && card.entry.id === test.secondId && card.landing > 0 && card.landing < 1 && card.opacity < 1,
                "A fresh member did not fall/fade onto the existing stack independently");
        }
    }
    Timer { interval: 10000; running: !Quickshell.env("DOTFILES_BANNER_PREVIEW"); onTriggered: test.check(false, "Timed out"); }
}
