import QtQuick
import Quickshell

// Run with a private fixture through isolated-gui's nested Wayland compositor.
Scope {
    id: test
    property var app: null
    property var button: null
    property int step: 0
    function check(value, message) {
        if (!value) { console.error("APPEARANCE FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "A private fixture is required");
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(component.status === Component.Ready, component.errorString());
        app = component.createObject(test);
        check(!!app, "Shell could not be created");
        app.pill.hoverExpanded = true;
        advance.start();
    }
    Timer {
        id: advance; interval: 400; repeat: true
        onTriggered: {
            switch (test.step++) {
            case 0: {
                test.button = test.find(test.app.pill.contentItem, "pillAppearanceButton");
                const controls = test.find(test.app.pill.contentItem, "pillControlButtons");
                test.check(!!test.button && test.button.enabled && test.button.icon === "moon", "Dark preference must show an enabled moon button");
                test.check(test.button.parent === controls.parent && test.button.x + test.button.width === controls.x,
                    "Appearance button must touch the left edge of the controls without a gap");
                test.button.clicked(Qt.LeftButton);
                break;
            }
            case 1:
                test.check(!test.app.appearance.dark && test.button.icon === "sun" && test.button.hint === "Switch to dark style", "Click must switch to light mode and offer dark mode");
                test.check(test.app.panel === "" && test.app.pill.pillState === "expanded", "Changing appearance must preserve the expanded controls");
                if (Quickshell.env("DOTFILES_APPEARANCE_PREVIEW"))
                    test.find(test.app.pill.contentItem, "floatingPill").grabToImage(result => result.saveToFile(Quickshell.env("DOTFILES_APPEARANCE_PREVIEW")));
                break;
            case 2:
                test.button.clicked(Qt.LeftButton);
                break;
            case 3:
                test.check(test.app.appearance.dark && test.button.icon === "moon", "Second click must restore dark mode");
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {darkMode: false});
                break;
            case 4:
                test.check(test.button.icon === "sun", "Icon must follow an external appearance change");
                console.warn("APPEARANCE PASS: flush control placement, light/dark clicks, moon/sun state, external preference changes, and unchanged panel state");
                Qt.quit();
            }
        }
    }
    Timer { interval: 10000; running: true; onTriggered: test.check(false, "Timed out"); }
}
