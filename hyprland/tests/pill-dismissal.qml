import QtQuick
import Quickshell

// Run with a private fixture on an isolated nested Wayland compositor.
Scope {
    id: test
    property var app: null
    property int step: 0
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
                test.app.toggle("bluetooth"); break;
            case 1:
                test.openGeometry = bar.paneGeometry;
                test.app.notifications.entries = [{id:"arrival", app:"Messages", summary:"New message", body:"Header must stay interactive", time:Date.now(), read:false}];
                test.app.bluetooth.fixtureDevices = [null, {address:"new", name:"New headset", connected:false, paired:true}];
                break;
            case 2:
                test.check(test.find(bar.contentItem, c => c.objectName === "pillHeader").opacity === 0, "Notification arrival exposed the header");
                test.check(bar.paneGeometry === test.openGeometry, "Notification arrival shifted the open view");
                test.check(!test.find(bar.contentItem, c => c.hint === "Close panel"), "The removed cross returned");
                test.check(test.find(bar.activePane, c => c.hint === "Connect to New headset").enabled, "Device replacement left a broken row");
                test.app.bluetooth.fixtureDevices = []; break;
            case 3:
                test.app.bluetooth.fixtureDevices = [{address:"new", name:"New headset", connected:true, paired:true}]; break;
            case 4:
                test.check(!!test.find(bar.activePane, c => c.hint === "Disconnect New headset"), "Device state did not update");
                bar.dismiss(); break;
            case 5:
                test.check(test.app.panel === "" && bar.mask.regions[0].item.objectName === "floatingPill", "Closing retained the full-screen input region");
                console.warn("DISMISSAL PASS: notification arrival, stable view, device churn, dismissal, input-region release");
                Qt.quit();
            }
        }
    }
    Timer { interval: 5000; running: true; onTriggered: test.check(false, "Timed out") }
}
