import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Run with a shell fixture on the isolated helper's nested Wayland compositor.
Scope {
    id: test
    property var app: null
    property int step: 0
    property var portal: ({id: 10, name: "xdg-desktop-portal-hyprland",
                          properties: {"media.name": "xdph-streaming-test"}})
    property var camera: ({id: 20, name: "camera", properties: {"media.name": "Camera"}})
    function check(value, message) {
        if (!value) { console.error("SHARING FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function find(item, predicate) {
        if (predicate(item)) return item;
        for (const child of item.children || []) { const found = find(child, predicate); if (found) return found; }
        return null;
    }
    function state(sources, links) {
        app.fixtureData = {recording: true, screenSources: sources, screenLinks: links};
    }
    function expect(active, message) {
        check(app.screenSharing === active, message);
        const indicator = find(app.pill.contentItem, c => c.objectName === "pillScreenSharingIndicator");
        check(!!indicator && indicator.visible === active, "Indicator visibility: " + message);
        check(!find(app.pill.contentItem, c => c.hint === "Stop recording"), "Recording button returned");
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "Private fixture required");
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(c.status === Component.Ready, c.errorString());
        app = c.createObject(test);
        check(!!app, "Shell creation failed");
        app.pill.hoverExpanded = true;
    }
    Timer {
        interval: 300; repeat: true; running: !!test.app
        onTriggered: {
            switch (test.step++) {
            case 0: test.state([], []); break;
            case 1:
                test.expect(false, "Local recording alone must have no icon");
                test.state([test.camera], [{source:test.camera, state:PwLinkState.Active}]); break;
            case 2:
                test.expect(false, "Camera is not a screen share");
                test.state([test.portal], []); break;
            case 3:
                test.expect(false, "Unconsumed portal stream is not sharing");
                test.state([test.portal], [{source:test.portal, state:PwLinkState.Paused}]); break;
            case 4:
                test.expect(false, "Paused stream is not actively sharing");
                test.state([test.portal], [{source:test.portal, state:PwLinkState.Active},
                                          {source:test.portal, state:PwLinkState.Active}]); break;
            case 5:
                test.expect(true, "Active share must show the icon");
                test.state([test.portal], [{source:test.portal, state:PwLinkState.Active}]); break;
            case 6:
                test.expect(true, "One consumer stopping must keep the remaining share visible");
                test.state([], [{source:test.portal, state:PwLinkState.Active}]); break;
            case 7:
                test.expect(false, "Removed source must clear the icon even before links disappear");
                test.state([], []); break;
            case 8:
                test.expect(false, "Stopped share must clear the icon");
                console.warn("SHARING PASS: local recording, camera, idle, paused, active, multiple consumers, teardown");
                Qt.quit();
            }
        }
    }
    Timer { interval: 6000; running: true; onTriggered: test.check(false, "Timed out") }
}
