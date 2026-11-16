import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

Scope {
    id: test
    property var app: null
    property real lastHeight: 40
    property int openingFrames: 0
    property int closingFrames: 0
    TestResult { id: objects }
    Component.onCompleted: {
        if (!Quickshell.env("DOTFILES_SHELL_FIXTURE")) throw Error("Private shell fixture required");
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        if (component.status !== Component.Ready) throw Error(component.errorString());
        app = component.createObject(test);
        if (!app) throw Error(component.errorString());
    }
    Timer {
        interval: 16; running: !!test.app; repeat: true
        onTriggered: {
            const height = test.app.pill.pillGeometry.height;
            if (height > 40 && height < 428 && height !== test.lastHeight) {
                if (test.app.panel === "portal") test.openingFrames++;
                else test.closingFrames++;
            }
            test.lastHeight = height;
        }
    }
    IpcHandler {
        target: "portalPillTest"
        function state(): string {
            if (!test.app) return "{}";
            return JSON.stringify({panel: test.app.panel, active: test.app.portal.active,
                apps: test.app.portal.data.apps || [], width: test.app.pill.pillGeometry.width,
                height: test.app.pill.pillGeometry.height, opening: test.openingFrames,
                closing: test.closingFrames, content: !!test.app.pill.activePane, kind: test.app.portal.data.kind,
                desiredHeight: test.app.pill.activePane?.desiredHeight || 0, canAccept: test.app.pill.activePane?.canAccept || false,
                results: test.app.pill.activePane?.results?.length || 0,
                hidden: test.app.pill.hidden, idleHidden: test.app.pill.idleHidden});
        }
        function cancel(): void { test.app.pill.dismiss(); }
        function filter(query: string): void { objects.findChild(test.app.pill.activePane, "portalAppSearch").text = query; }
        function accept(index: int): void { test.app.pill.activePane.chooseApp(index); test.app.pill.activePane.accept(); }
        function permission(allow: bool): void {
            test.app.pill.activePane.selections = {remember: "true"};
            test.app.pill.activePane.decide(allow ? 0 : 1);
        }
        function share(tab: string, identity: string, region: bool): void {
            const pane = test.app.pill.activePane;
            pane.setTab(tab); pane.choose(identity); pane.remember = true;
            if (region) { pane.regionMode = true; pane.region = [10, 20, 320, 180]; }
        }
        function submit(): void { test.app.pill.activePane.accept(); }
        function fullscreen(enabled: bool): void { test.app.fixtureData = Object.assign({}, test.app.fixtureData, {fullscreen: enabled}); }
    }
}
