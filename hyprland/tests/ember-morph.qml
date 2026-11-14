import QtQuick
import Quickshell

Scope {
    id: test
    property var app: null
    property var shape: null
    property var previous: null
    property int step: 0
    property int jumpFrames: 0
    property bool sawTakeoff: false
    property bool sawLanding: false
    function check(value, message) {
        if (!value) { console.error("MORPH FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function descendants(item) {
        let result = [];
        for (const child of item.children || []) { result.push(child); result = result.concat(descendants(child)); }
        return result;
    }
    function docked() {
        const found = descendants(app.pill.contentItem).filter(c => c.objectName === "emberShape");
        check(found.length === 1, "There must be exactly one physical shape");
        if (!shape) shape = found[0];
        check(found[0] === shape, "The shared shape was replaced");
        check(app.emberTarget && app.emberTarget.occupied, "Destination did not claim its highlight");
        check(app.pill.ember.dock === app.emberTarget && shape.parent === app.emberTarget, "Shape did not dock beneath destination content");
        check(shape.width === app.emberTarget.width && shape.height === app.emberTarget.height, "Shape did not become the destination element");
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "A private fixture is required");
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(component.status === Component.Ready, component.errorString());
        app = component.createObject(test);
        app.pill.hoverExpanded = true;
        advance.start();
    }
    Timer {
        interval: 16; repeat: true; running: true
        onTriggered: {
            if (!test.app || !test.shape) return;
            const ember = test.app.pill.ember;
            if (ember.phase === "takeoff") test.sawTakeoff = true;
            if (ember.phase === "landing") test.sawLanding = true;
            if (ember.phase !== "jump") return;
            test.check(!ember.dock, "The bead stayed attached while jumping");
            test.check(test.shape.width >= 8 && test.shape.width <= 12 && test.shape.height >= 8 && test.shape.height <= 11, "The element did not become a dot in flight");
            test.check(test.shape.visible && test.shape.opacity > 0.95, "The jumping dot was not visible");
            test.jumpFrames++;
        }
    }
    Timer {
        id: advance; interval: 600; repeat: true
        onTriggered: {
            switch (test.step++) {
            case 0:
                test.docked(); test.check(test.shape.height === 7 && test.shape.width > 7, "Workspace did not become the active bar");
                test.app.toggle("launcher"); break;
            case 1:
                test.docked(); test.check(test.shape.width === 3 && test.app.emberTarget.caret, "Launcher did not become its caret");
                test.app.toggle("media"); break;
            case 2:
                test.docked(); test.check(test.app.emberTarget.parent.color.a === 0, "Media kept a duplicate slider handle");
                test.app.toggle("mixer"); break;
            case 3: {
                test.docked(); test.previous = test.app.emberTarget;
                test.check(test.previous.parent.color.a === 0, "Mixer kept a duplicate slider handle");
                const sliders = test.descendants(test.app.pill.activePane).filter(c => c.handle !== undefined && c.visualPosition !== undefined && c.to === 1);
                test.check(sliders.length >= 3, "Brightness sliders did not load");
                test.app.pill.activePane.follow(sliders[sliders.length - 1]); break;
            }
            case 4:
                test.docked(); test.check(!test.previous.occupied && test.previous.parent.color.a > 0, "Previous slider handle was not restored");
                test.app.toggle("notifications"); break;
            case 5:
                test.docked(); test.check(test.shape.width === 42 && test.shape.height === 42, "Calendar did not become the selected date");
                test.previous = test.app.emberTarget;
                test.app.agenda.selectDate(new Date(test.app.clock.date.getTime() + 86400000)); break;
            case 6:
                test.docked(); test.check(test.app.emberTarget !== test.previous, "Calendar selection did not move the shape");
                test.app.notifications.entries = [{id:"morph", app:"Fixture", summary:"Unread", body:"Notification", time:Date.now(), read:false, critical:false}];
                test.app.pill.activePane.notificationMode = true; break;
            case 7:
                test.docked(); test.check(test.shape.width === 3 && test.shape.height > 20, "Notification did not become an accent strip");
                test.app.toggle("bluetooth"); break;
            case 8:
                test.docked(); test.check(test.shape.width === 20 && test.shape.height === 20, "Bluetooth did not become the switch thumb");
                test.app.bluetooth.togglePower(); break;
            case 9:
                test.docked(); test.app.toggle("ethernet"); break;
            case 10:
                test.docked(); test.check(test.shape.height === 32 && test.shape.width > 40, "Network did not become the active status capsule");
                test.app.toggle("system"); break;
            case 11:
                test.docked(); test.check(test.shape.width === 82 && test.shape.height === 38, "System did not become the metric value capsule");
                test.app.toggle("power"); break;
            case 12:
                test.check(!test.app.emberTarget && !test.shape.visible, "Power chose an action without interaction");
                test.descendants(test.app.pill.activePane).find(c => c.hint === "Lock").forceActiveFocus(); break;
            case 13:
                test.docked(); test.check(test.shape.width === 70 && test.shape.height === 60, "Power did not become the action background");
                test.app.gesture("hide", "100");
                test.check(!test.shape.visible, "Super hold did not hide the shape immediately"); break;
            case 14:
                test.app.gesture("show", "200"); break;
            case 15:
                test.docked(); test.check(test.shape.visible, "Super release did not restore the shape");
                test.app.panel = ""; test.app.pill.hoverExpanded = false; break;
            case 16:
                test.check(!test.shape.visible && !test.app.emberTarget, "Collapsed pill kept a highlight");
                test.app.pill.retained = {}; test.app.toggle("notifications"); break;
            case 17:
                test.docked();
                test.check(test.jumpFrames > 10 && test.sawTakeoff && test.sawLanding, "Missing takeoff, visible dot flight, or landing morph");
                console.warn("MORPH PASS: one shape, docking, replacement handles, calendar/date/card morphs, Bluetooth thumb, network status, metric bar, power focus, instant hold/release, collapse, and retained-view destruction");
                Qt.quit();
            }
        }
    }
    Timer { interval: 16000; running: true; onTriggered: test.check(false, "Morph test timed out"); }
}
