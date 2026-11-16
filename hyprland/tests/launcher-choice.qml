import QtQuick
import QtTest
import Quickshell

Scope {
    id: test
    property var pane: null
    property var window: null
    property var events: []
    TestResult { id: objects }
    QtObject {
        id: shell
        property bool fixture: true
        property bool emberEnabled: false
        property var emberTarget: null
        property var applications: null
        property var pill: null
        property string helper: ""
        property string panel: "launcher"
        property var fixtureData: ({apps: [
            {id: "alpha.desktop", name: "Alpha Document", description: "View documents", icon: ""},
            {id: "beta.desktop", name: "Beta Editor", description: "Edit text", icon: ""}
        ]})
        function fixtureEvent(name, data) { test.events.push({name: name, data: data}); }
    }
    Component.onCompleted: {
        const source = Quickshell.env("DOTFILES_SHELL_SOURCE");
        const theme = Qt.createComponent("file:" + source + "/PillTheme.qml").createObject(test);
        const component = Qt.createComponent("file:" + source + "/LauncherPane.qml");
        if (component.status !== Component.Ready) throw Error(component.errorString());
        window = Qt.createQmlObject('import Quickshell; FloatingWindow { implicitWidth: 560; implicitHeight: 428; visible: true }', test);
        pane = component.createObject(window.contentItem, {shell: shell, theme: theme, width: 536, height: 408, x: 12, y: 8});
        if (!pane) throw Error(component.errorString());
    }
    Timer {
        interval: 500; running: true
        onTriggered: {
            const list = objects.findChild(test.pane, "pillApps");
            if (list.count !== 2 || !list.itemAtIndex(0) || !list.itemAtIndex(0).selected)
                throw Error("Launcher lost its initial selection or shared result delegate");
            test.pane.moveSelection(1);
            test.pane.launch();
            if (test.events.length !== 1 || test.events[0].data.id !== "app:beta.desktop")
                throw Error("Launcher selection no longer opens the expected application");
            console.warn("LAUNCHER CHOICE PASS: shared result rows preserve initial selection, navigation, and activation");
            Qt.quit();
        }
    }
}
