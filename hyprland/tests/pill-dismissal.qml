import QtQuick
import Quickshell

// Run with a private fixture on an isolated nested Wayland compositor.
Scope {
    id: test
    property var app: null
    property int step: 0
    property rect expandedGeometry
    property bool watchIndicator: false
    property bool sawIndicatorFade: false
    property rect openGeometry
    function check(value, message) {
        if (!value) { console.error("DISMISSAL FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function find(item, predicate) {
        if (predicate(item)) return item;
        for (const child of item.children || []) { const match = find(child, predicate); if (match) return match; }
        return null;
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "Private fixture required");
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(c.status === Component.Ready, c.errorString());
        app = c.createObject(test);
    }
    Timer {
        interval: 350; repeat: true; running: !!test.app
        onTriggered: {
            const bar = test.app.pill;
            switch (test.step++) {
            case 0:
                bar.hoverExpanded = true; break;
            case 1:
                test.expandedGeometry = bar.pillGeometry;
                test.watchIndicator = true;
                test.app.notifications.entries = [{id:"dot", app:"Messages", summary:"New message", time:Date.now(), read:false}];
                break;
            case 2:
                test.check(test.sawIndicatorFade, "Notification indicator appeared without animating");
                test.check(bar.expanded && bar.pillGeometry === test.expandedGeometry, "Notification arrival retargeted the expanded pill");
                test.app.notifications.entries = []; break;
            case 3:
                test.check(bar.expanded && bar.pillGeometry === test.expandedGeometry, "Notification removal retargeted the expanded pill");
                test.watchIndicator = false;
                bar.hoverExpanded = false; break;
            case 4:
                break;
            case 5:
                test.app.toggle("bluetooth"); break;
            case 6:
                test.openGeometry = bar.paneGeometry;
                test.app.notifications.entries = [{id:"arrival", app:"Messages", summary:"New message", body:"Header must stay interactive", time:Date.now(), read:false}];
                test.app.bluetooth.fixtureDevices = [null, {address:"new", name:"New headset", connected:false, paired:true}];
                break;
            case 7:
                test.check(test.find(bar.contentItem, c => c.objectName === "pillHeader").opacity === 0, "Notification arrival exposed the header");
                test.check(bar.paneGeometry === test.openGeometry, "Notification arrival shifted the open view");
                test.check(!test.find(bar.contentItem, c => c.hint === "Close panel"), "The removed cross returned");
                test.check(test.find(bar.activePane, c => c.hint === "Connect to New headset").enabled, "Device replacement left a broken row");
                test.app.bluetooth.fixtureDevices = []; break;
            case 8:
                test.app.bluetooth.fixtureDevices = [{address:"new", name:"New headset", connected:true, paired:true}]; break;
            case 9:
                test.check(!!test.find(bar.activePane, c => c.hint === "Disconnect New headset"), "Device state did not update");
                bar.dismiss(); break;
            case 10:
                test.check(test.app.panel === "" && bar.mask.regions[0].item.objectName === "floatingPill", "Closing retained the full-screen input region");
                console.warn("DISMISSAL PASS: animated indicator, stable expanded header and open view, device churn, dismissal, input-region release");
                Qt.quit();
            }
        }
    }
    Timer {
        interval: 16; repeat: true; running: test.watchIndicator
        onTriggered: {
            const bar = test.app.pill;
            const dot = test.find(bar.contentItem, c => c.objectName === "pillNotificationIndicator");
            if (dot.opacity > 0 && dot.opacity < 1) test.sawIndicatorFade = true;
            test.check(bar.pillGeometry === test.expandedGeometry && bar.detailsOpacity === 1,
                       "Indicator animation moved or faded the expanded header");
        }
    }
    Timer { interval: 6000; running: true; onTriggered: test.check(false, "Timed out") }
}
