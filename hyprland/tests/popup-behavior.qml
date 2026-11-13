import QtQuick
import Quickshell

// Run with isolated-gui, setting DOTFILES_SHELL_SOURCE to config/shell.
// All panel services and actions are fixtures; no user session is accessed.
Scope {
    id: test
    property var dialog
    property int phase: 0
    property double started: Date.now()
    property double closeElapsed: 0
    function check(condition, message) {
        if (!condition) { console.error("POPUP REGRESSION FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function choose(name, x, width) {
        fixture.panelOriginX = x;
        fixture.panelOriginWidth = width;
        fixture.panel = name;
        dialog.sync();
        if (dialog.pendingOpen) Qt.callLater(dialog.frameReady);
        started = Date.now();
    }
    Window {
        id: preview
        visible: true
        width: 1280; height: 900
        title: "Popup transition regression"
        color: "#68788c"
        Text {
            visible: !!test.dialog
            x: test.dialog ? test.dialog.targetX + 24 : 0
            y: 62; color: "white"; font.pixelSize: 18
            text: test.dialog ? test.dialog.shown : ""
        }
    }
    QtObject {
        id: fixture
        property string panel: ""
        property real panelOriginX: 0
        property real panelOriginWidth: 80
    }
    Component.onCompleted: {
        const source = "file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/";
        const palette = Qt.createComponent(source + "ShellTheme.qml");
        check(palette.status === Component.Ready, palette.errorString());
        const component = Qt.createComponent(source + "PopupTransition.qml");
        check(component.status === Component.Ready, component.errorString());
        dialog = component.createObject(preview.contentItem, {shell: fixture, theme: palette.createObject(test), screenWidth: 1280, screenHeight: 900});
        check(!!dialog, "Could not create the popup");
        const bubble = Qt.createComponent(source + "PopupBubble.qml");
        check(bubble.status === Component.Ready, bubble.errorString());
        check(!!bubble.createObject(preview.contentItem, {
            width: 1280, height: 900, panelHeight: 30, wing: 12,
            originX: Qt.binding(() => test.dialog.originX),
            originWidth: Qt.binding(() => test.dialog.originWidth),
            progress: Qt.binding(() => test.dialog.progress),
            targetRect: Qt.binding(() => Qt.rect(test.dialog.targetX, 38, test.dialog.targetWidth, test.dialog.targetHeight)),
            z: -1
        }), "Could not create the popup outline");
        check(dialog.animationDuration === 140, "Unexpected animation duration");
        choose("power", 1194, 80);
    }
    Timer {
        interval: 10; repeat: true; running: !!test.dialog
        onTriggered: {
            const elapsed = Date.now() - test.started;
            const d = test.dialog;
            if (test.phase === 0 && d.progress === 1) {
                test.choose("ethernet", 1050, 80);
                test.check(d.shown === "ethernet" && d.expanded && d.progress === 1, "Switch waited for collapse");
                test.phase = 1;
            } else if (test.phase === 1 && elapsed >= 40) {
                test.check(d.progress === 1, "Switch collapsed the popup");
                test.check(d.targetWidth > 316 && d.targetWidth < 390, "Width did not interpolate");
                test.choose("bluetooth", 1122, 80);
                test.check(d.shown === "bluetooth", "Second switch was queued");
                test.phase = 2;
            } else if (test.phase === 2 && elapsed >= 25) {
                test.choose("notifications", 540, 200);
                test.check(d.shown === "notifications" && d.progress === 1, "Rapid switch was queued");
                test.phase = 3;
            } else if (test.phase === 3 && elapsed >= 180 && !d.moving) {
                test.check(d.originX === 540 && d.originWidth === 200, "Attachment did not settle at latest button");
                test.check(d.targetWidth === d.requestedWidth && d.targetHeight === d.requestedHeight && d.targetX === d.requestedX, "Popup geometry did not settle");
                test.choose("", 540, 200);
                test.phase = 4;
            } else if (test.phase === 4 && elapsed >= 40) {
                test.check(d.progress > 0 && d.progress < 1, "Close did not animate");
                test.choose("power", 1194, 80);
                test.check(d.shown === "power" && d.expanded && d.progress > 0, "Switch during close waited for collapse");
                test.phase = 5;
            } else if (test.phase === 5 && elapsed >= 180 && !d.moving && d.progress === 1) {
                test.choose("", 1194, 80);
                test.phase = 6;
            } else if (test.phase === 6 && d.progress === 0) {
                test.check(!d.visible && !d.shown, "Closed popup remained visible");
                test.closeElapsed = elapsed;
                test.check(elapsed >= 100 && elapsed <= 250, "Close took an unexpected amount of time: " + elapsed);
                test.choose("ethernet", 1050, 80);
                test.phase = 7;
            } else if (test.phase === 7 && d.progress === 1) {
                test.check(elapsed >= 100 && elapsed <= 280, "Open took an unexpected amount of time: " + elapsed);
                test.check(Math.abs(elapsed - test.closeElapsed) <= 70, "Opening and closing timings differ");
                console.warn("POPUP REGRESSION PASS: matched timing, immediate morphs, rapid switches, close interruption; close", test.closeElapsed, "ms; open", elapsed, "ms");
                Qt.quit();
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: test.check(false, "Popup sequence timed out at phase " + test.phase) }
}
