import QtQuick
import Quickshell

// Load the real shell's helper path and run its normal application-indexing
// process. All windows and D-Bus services belong to the isolated test desktop.
Scope {
    id: test
    property var app: null
    property var launcher: null
    property int attempts: 0
    function check(condition, message) {
        if (!condition) { console.error("LAUNCHER LOADING FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function component(name) {
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/" + name + ".qml");
        check(c.status === Component.Ready, c.errorString());
        return c;
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "Shell must use fixture services");
        app = component("shell").createObject(test);
        check(!!app, "Could not load shell");
        check(app.helper.startsWith("/"), "Helper is not a filesystem path: " + app.helper);
        // Only application indexing uses the real backend; no apps are launched.
        const backendShell = {fixture: false, helper: app.helper, panel: ""};
        launcher = component("LauncherPane").createObject(test, {shell: backendShell, theme: component("ShellTheme").createObject(test)});
        check(!!launcher, "Could not load launcher");
        verify.start();
    }
    Timer {
        id: verify
        interval: 100; repeat: true
        onTriggered: {
            test.check(!test.launcher.error, test.launcher.error);
            if (test.launcher.loading) {
                test.check(++test.attempts < 100, "Application index timed out");
                return;
            }
            test.check(test.launcher.installedApps.length > 0, "No installed applications were loaded");
            test.check(test.launcher.matches.length === test.launcher.installedApps.length, "Loaded apps are absent from results");
            console.warn("LAUNCHER LOADING PASS:", test.launcher.installedApps.length, "applications loaded through", test.app.helper);
            Qt.quit();
        }
    }
}
