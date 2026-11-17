import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

Scope {
    id: test
    property var app: null
    property int openingFrames: 0
    property int closingFrames: 0
    property int emberFrames: 0
    property real previousHeight: 40
    TestResult { id: objects }
    Component.onCompleted: {
        if (!Quickshell.env("DOTFILES_SHELL_FIXTURE")) throw Error("Private fixture required");
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        if (component.status !== Component.Ready) throw Error(component.errorString());
        app = component.createObject(test);
        if (!app) throw Error(component.errorString());
    }
    Timer {
        interval: 16; running: !!test.app; repeat: true
        onTriggered: {
            if (test.app.pill.ember.moving) test.emberFrames++;
            const height = test.app.pill.pillGeometry.height;
            if (height !== test.previousHeight && height > 40) {
                if (test.app.panel === "credentials") test.openingFrames++;
                else test.closingFrames++;
            }
            test.previousHeight = height;
        }
    }
    IpcHandler {
        target: "credentialTest"
        function state(): string {
            if (!test.app) return "{}";
            return JSON.stringify({panel: test.app.panel, active: test.app.credentials.active,
                kind: test.app.credentials.data.kind || "", code: test.app.credentials.data.code || "",
                fields: (test.app.credentials.data.fields || []).length,
                width: test.app.pill.pillGeometry.width, height: test.app.pill.pillGeometry.height,
                opening: test.openingFrames, closing: test.closingFrames,
                heading: test.app.pill.activePane?.heading || "", icon: test.app.pill.activePane?.headingIcon || "",
                body: test.app.credentials.data.body || "",
                ember: test.app.pill.ember.target?.objectName || "",
                dock: test.app.pill.ember.dock?.objectName || "", emberFrames: test.emberFrames,
                canAccept: !!test.app.pill.activePane?.canAccept});
        }
        function fill(index: int, value: string): void {
            test.app.pill.activePane.setInput(index, value);
        }
        function accept(): void { test.app.pill.activePane.accept(); }
        function inputPoint(index: int): string { return JSON.stringify(test.app.pill.activePane.inputPoint(index)); }
        function controlPoint(name: string, index: int): string { return JSON.stringify(test.app.pill.activePane.controlPoint(name, index)); }
        function revealed(index: int): bool { return test.app.pill.activePane.inputRevealed(index); }
        function cancel(): void { test.app.pill.dismiss(); }
    }
}
