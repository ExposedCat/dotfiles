import QtQuick
import Quickshell

// Run through isolated-gui with DOTFILES_SHELL_SOURCE and private XDG_STATE_HOME.
Scope {
    id: test
    property var store
    property var banners
    property var first
    property string firstId: ""
    property string secondId: ""
    property string thirdId: ""
    property var originalBanner
    property real exitHeight: 0
    property int phase: 0
    function check(condition, message) {
        if (!condition) { console.error("BANNER REGRESSION FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function component(name) {
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/" + name + ".qml");
        check(c.status === Component.Ready, c.errorString());
        return c;
    }
    function findBanner(item, id) {
        if (item.objectName === "banner:" + id) return item;
        for (const child of (item.children || [])) {
            const result = findBanner(child, id);
            if (result) return result;
        }
        return null;
    }
    function message(id) {
        const callbacks = {};
        const n = {id: id, appName: "Test", desktopEntry: "test", appIcon: "", image: "", summary: "Notification " + id,
            body: "A banner keeps its pixels until the slide finishes.", expireTimeout: 0, urgency: 1,
            transient: false, actions: [], hasInlineReply: false};
        for (const name of ["summary", "body", "appName", "appIcon", "image", "expireTimeout", "urgency", "transient"])
            n[name + "Changed"] = {connect: callback => { callbacks[name] = callback; }};
        n.closed = {connect: callback => { callbacks.closed = callback; }};
        n.expire = () => { if (callbacks.closed) callbacks.closed(1); };
        n.dismiss = () => { if (callbacks.closed) callbacks.closed(2); };
        n.update = summary => { n.summary = summary; if (callbacks.summary) callbacks.summary(); };
        return n;
    }
    FloatingWindow {
        id: window
        title: "Notification banner motion test"
        implicitWidth: 800; implicitHeight: 500
        color: "#292929"
        visible: true
        mask: Region { regions: test.banners ? test.banners.inputRegions : [] }
    }
    Component.onCompleted: {
        // Compile the real surface too; no layer-shell window is instantiated on X11.
        component("Overlays");
        store = component("Notifications").createObject(test, {statePath: Quickshell.env("XDG_STATE_HOME") + "/banner-test.json"});
        const theme = component("ShellTheme").createObject(test);
        banners = component("NotificationBanners").createObject(window.contentItem,
            {theme: theme, store: store, width: 454, x: 346, y: theme.panelHeight + theme.panelGap});
        check(banners.y === 38, "Banners do not align with the reserved panel space");
        first = message(1);
        begin.start();
    }
    Timer {
        id: begin; interval: 100
        onTriggered: {
            store.receive(first); firstId = store.popups[0].id;
            Qt.callLater(() => {
                originalBanner = test.findBanner(banners, firstId);
                check(!!originalBanner, "Banner was not created");
                check(originalBanner.offset >= originalBanner.travel - 1, "Entrance did not start beyond the right screen edge");
                tick.interval = 80; tick.start();
            });
        }
    }
    Timer {
        id: tick; interval: 80
        onTriggered: {
            const card = test.findBanner(banners, firstId);
            const visual = card ? card.children.find(child => child.objectName === "notification-banner-card") : null;
            switch (phase++) {
            case 0:
                check(card.offset > 0 && card.offset < card.travel, "Entrance did not slide left");
                check(visual.opacity === 1 && card.height > 0, "Entrance faded or collapsed");
                interval = 250; break;
            case 1:
                check(Math.abs(card.offset) < 1, "Entrance did not settle at its resting position");
                check(window.width - banners.x - card.width === banners.theme.panelGap, "Right inset does not match the panel's bottom gap");
                first.update("Updated in place"); interval = 40; break;
            case 2:
                check(card === originalBanner && card.entry.summary === "Updated in place" && Math.abs(card.offset) < 1, "A content update replayed the entrance");
                exitHeight = card.height; store.hidePopup(firstId); interval = 80; break;
            case 3:
                check(banners.presentationCount === 1 && card.offset > 0 && card.offset < card.travel, "Expiry destroyed the last banner before its slide finished");
                check(visual.opacity === 1 && card.height === exitHeight, "Exit faded or collapsed");
                check(!card.enabled && card.inputRegion.item === card, "Exit remained interactive or lost its moving mask");
                interval = 250; break;
            case 4:
                check(banners.presentationCount === 0, "An expired banner was not retired");
                check(store.entries.length === 1, "Banner expiry incorrectly deleted notification history");
                store.receive(first); interval = 300; break;
            case 5:
                originalBanner = card; store.hidePopup(firstId); interval = 80; break;
            case 6:
                check(card.offset > 0, "Reversal test never began exiting");
                store.receive(first); interval = 300; break;
            case 7:
                check(card === originalBanner && Math.abs(card.offset) < 1 && banners.presentationCount === 1, "An update during exit duplicated or lost the card");
                banners.active = false; interval = 300; break;
            case 8:
                check(banners.presentationCount === 0, "Opening the center did not slide banners out");
                banners.active = true; interval = 300; break;
            case 9:
                check(banners.presentationCount === 1 && Math.abs(card.offset) < 1, "Closing the center did not restore a still-live banner");
                store.remove(firstId); interval = 100; break;
            case 10:
                check(card && card.offset > 0 && visual.opacity === 1 && card.height > 0, "Explicit dismissal skipped the horizontal exit");
                interval = 250; break;
            case 11:
                check(banners.presentationCount === 0 && store.entries.length === 0, "Dismissal leaked a delegate or history entry");
                store.receive(message(2)); secondId = store.popups[0].id;
                store.receive(message(3)); thirdId = store.popups[0].id;
                interval = 300; break;
            case 12:
                check(banners.presentationCount === 2 && banners.inputRegions.length === 2, "Multiple banners did not get independent input regions");
                store.hidePopup(secondId); interval = 80; break;
            case 13:
                check(test.findBanner(banners, secondId).offset > 0 && Math.abs(test.findBanner(banners, thirdId).offset) < 1, "Removing one banner moved the other horizontally");
                interval = 250; break;
            case 14:
                check(banners.presentationCount === 1 && banners.inputRegions.length === 1, "Retirement leaked an input region");
                store.hidePopup(thirdId); interval = 300; break;
            case 15:
                check(banners.presentationCount === 0 && banners.inputRegions.length === 0, "The last input region was not released");
                console.warn("BANNER REGRESSION PASS: entrance, expiry, last-banner exit, reversal, center toggle, dismissal, per-card input regions, panel alignment");
                Qt.quit(); return;
            }
            restart();
        }
    }
    Timer { interval: 8000; running: true; onTriggered: { test.check(false, "Timed out waiting for banner animation"); } }
}
