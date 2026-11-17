import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

// Run through native-ui.py on the isolated desktop, with a fake session-info
// executable and an external snapshot file. Never changes a real keyboard/radio.
Scope {
    id: test
    property var app: null
    property var keyboard: null
    property int phase: 0
    TestResult { id: objects }
    QtObject {
        id: keyboardShell
        property bool fixture: false
        property string backend: Quickshell.env("DOTFILES_LAYOUT_BACKEND")
    }
    FileView { id: snapshot; path: Quickshell.env("DOTFILES_LAYOUT_SNAPSHOT"); blockLoading: true; blockWrites: true; atomicWrites: true; printErrors: false }
    function check(value, message) {
        if (!value) { console.error("KEYBOARD/BLUETOOTH FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function state(device, layout, delay) { snapshot.setText(JSON.stringify({keyboard: device, layout: layout, delay: delay || 0})); }
    function find(item, predicate) {
        if (predicate(item)) return item;
        for (const child of item.children || []) { const found = find(child, predicate); if (found) return found; }
        return null;
    }
    Component.onCompleted: {
        check(!!Quickshell.env("ISOLATED_GUI_SESSION") && !!Quickshell.env("DOTFILES_SHELL_FIXTURE") && !!keyboardShell.backend && !!snapshot.path, "Isolated fixture inputs required");
        const source = "file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/";
        state("keyboard-a", "English (US)");
        let component = Qt.createComponent(source + "KeyboardLayout.qml");
        check(component.status === Component.Ready, component.errorString());
        keyboard = component.createObject(test, {shell: keyboardShell});
        component = Qt.createComponent(source + "shell.qml");
        check(component.status === Component.Ready, component.errorString());
        app = component.createObject(test);
        check(!!app && !!keyboard, "Fixture creation failed");
    }
    Timer {
        interval: 350; running: !!test.app; repeat: true
        onTriggered: {
            const app = test.app, keyboard = test.keyboard;
            switch (test.phase) {
            case 0:
                test.check(keyboard.keyboard === "keyboard-a" && keyboard.layout === "English (US)", "Initial primary keyboard snapshot");
                app.bluetooth.fixtureEnabled = false;
                app.toggle("bluetooth");
                break;
            case 1:
                test.check(objects.findChild(app.pill, "pillBluetoothButton").icon === "bluetooth-off", "Disabled pill icon");
                test.check(objects.findChild(app.pill.activePane, "bluetooth-header-icon").name === "bluetooth-off", "Disabled menu icon");
                test.check(!test.find(app.pill.activePane, item => item.text === "Bluetooth is off"), "Redundant off label must be removed");
                if (Quickshell.env("DOTFILES_PREVIEW_DIR")) objects.findChild(app.pill, "floatingPill").grabToImage(result => result.saveToFile(Quickshell.env("DOTFILES_PREVIEW_DIR") + "/bluetooth-off.png"));
                test.state("keyboard-a", "Russian");
                keyboard.handleEvent("activelayout", "keyboard-a,Russian");
                test.check(keyboard.layout === "Russian", "Primary keyboard events must update immediately");
                break;
            case 2:
                test.check(keyboard.layout === "Russian", "Primary snapshot must preserve the latest layout");
                test.state("keyboard-b", "English (US)");
                keyboard.handleEvent("activelayout", "keyboard-b,English (US)");
                break;
            case 3:
                test.check(keyboard.keyboard === "keyboard-b" && keyboard.layout === "English (US)", "A new primary keyboard must replace the startup keyboard");
                keyboard.handleEvent("activelayout", "keyboard-a,Russian");
                test.check(keyboard.layout === "English (US)", "Secondary keyboard must not overwrite the primary layout");
                break;
            case 4:
                test.check(keyboard.keyboard === "keyboard-b" && keyboard.layout === "English (US)", "Secondary event reconciliation");
                test.state("keyboard-b", "English (US)", 0.65);
                keyboard.refresh();
                break;
            case 5:
                test.state("keyboard-b", "Russian");
                keyboard.handleEvent("activelayout", "keyboard-b,Russian");
                break;
            case 6:
                test.check(keyboard.layout === "Russian", "An older in-flight snapshot must not undo a newer event");
                test.state("", "English (US)");
                keyboard.refresh();
                break;
            case 7:
                test.check(keyboard.keyboard === "keyboard-b" && keyboard.layout === "Russian", "Unavailable snapshots must preserve the last valid layout");
                test.state("keyboard-c", "English (US)");
                break;
            case 8:
                // No event/explicit refresh: the periodic snapshot must recover.
                if (keyboard.keyboard !== "keyboard-c") return;
                test.check(keyboard.layout === "English (US)", "Missed-event recovery");
                app.bluetooth.fixtureEnabled = true;
                test.check(objects.findChild(app.pill, "pillBluetoothButton").icon === "bluetooth", "Enabled pill icon must return");
                app.keyboardLayout.handleEvent("activelayout", "fixture,Russian");
                test.check(app.layout === "Russian" && app.layoutLabel === "RU", "Live shell label must bind to keyboard layout state");
                console.warn("BACKEND UI PASS: Bluetooth off/on icons, no off label; primary keyboard changes, secondary events, stale queries, unavailable snapshots, periodic recovery, and pill layout binding");
                Qt.quit();
                break;
            }
            test.phase++;
        }
    }
    Timer { interval: 12000; running: true; onTriggered: test.check(false, "Timed out at phase " + test.phase) }
}
