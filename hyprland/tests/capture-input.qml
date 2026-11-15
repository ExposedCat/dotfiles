import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Run with capture-input.py on the isolated helper's nested Wayland display.
Scope {
    id: test
    property var capture: null
    property var desktop: null
    property var events: []
    TestResult { id: objects }
    function surface() { return objects.findChild(capture, "captureSurface"); }
    function textField() { return objects.findChild(capture, "captureAnnotationInput"); }
    Window {
        id: underlying
        visible: true; width: 800; height: 600
        title: "Capture input observer"
        Item {
            anchors.fill: parent; focus: true
            Keys.onPressed: event => { test.events = test.events.concat(["press:" + event.key]); event.accepted = true; }
            Keys.onReleased: event => { test.events = test.events.concat(["release:" + event.key]); event.accepted = true; }
        }
    }
    Component.onCompleted: {
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_CAPTURE_SOURCE") + "/CaptureController.qml");
        if (component.status !== Component.Ready) throw Error(component.errorString());
        capture = component.createObject(test, {persistent: true});
        if (!capture) throw Error("Could not create capture controller");
    }
    IpcHandler {
        target: "captureInputTest"
        function open(): bool {
            test.events = [];
            return test.capture.openSession(Quickshell.env("DOTFILES_CAPTURE_SESSION"));
        }
        function openRecord(): bool {
            const opened = open();
            if (opened) test.capture.data = Object.assign({}, test.capture.data, {mode: "record"});
            return opened;
        }
        function edit(): bool {
            const field = test.textField();
            if (!field) return false;
            field.x = 120; field.y = 120; field.text = ""; field.visible = true; field.forceActiveFocus();
            return true;
        }
        function launcher(): bool {
            if (!test.desktop) {
                const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_CAPTURE_SOURCE") + "/../shell/shell.qml");
                if (component.status !== Component.Ready) throw Error(component.errorString());
                test.desktop = component.createObject(test);
                test.desktop.fixtureData = Object.assign({}, test.desktop.fixtureData, {apps: [
                    {id: "terminal.desktop", name: "Terminal"}, {id: "telegram.desktop", name: "Telegram"}
                ]});
                // Sway has no HyprlandFocusGrab. Emulate its keyboard ownership
                // while exercising the real Bar and capture handoff over IPC.
                test.desktop.pill.WlrLayershell.keyboardFocus = Qt.binding(() =>
                    test.desktop.panel && !test.desktop.captureActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None);
                test.capture.shellConfig = Quickshell.env("DOTFILES_CAPTURE_TEST_CONFIG");
            }
            test.desktop.gesture("tap");
            return test.desktop.panel === "launcher";
        }
        function toolbarPoint(name: string): string {
            const view = test.surface();
            test.capture.current = view.display.name;
            const tools = objects.findChild(view, "captureTools");
            const button = tools.itemAt(["pen", "arrow", "box", "text", "blur"].indexOf(name));
            const position = button.mapToItem(view.contentItem, button.width / 2, button.height / 2);
            return JSON.stringify({x:view.display.x + position.x, y:view.display.y + position.y});
        }
        function whiteInk(): void { test.capture.ink = "#ffffff"; }
        function undoStroke(): void { test.capture.undo(); }
        function finishSelection(): void { test.surface().finish(); }
        function toggleCursor(): void { test.capture.includeCursor = !test.capture.includeCursor; test.capture.remember(); }
        function prepareRecord(): string {
            test.capture.data = Object.assign({}, test.capture.data, {mode:"record"});
            test.capture.keyPressed(Qt.Key_Return, 0, false);
            test.capture.beginRecording();
            return JSON.stringify(test.capture.recordArguments);
        }
        function abortRecord(): void { test.capture.closeSession(); test.capture.keyReleased(Qt.Key_Return, false); }
        function paintAcross(): void { const r = test.capture.selection; test.capture.strokes = [{type:"box",x:r.x+10,y:r.y+10,x2:r.x+r.width-10,y2:r.y+r.height-10,color:"#ffffff"}]; }
        function query(): void { test.desktop.pill.activePane.children.find(c => c.objectName === "pillSearch").text = "te"; }
        function choose(): void { test.desktop.pill.activePane.choose(1); }
        function loseFocus(): void { test.desktop.pill.lostFocus(); }
        function state(): string {
            const view = test.surface(), field = test.textField();
            const scene = objects.findChild(test.capture, "captureScene:" + test.capture.current);
            const search = test.desktop?.pill.activePane?.children.find(c => c.objectName === "pillSearch");
            return JSON.stringify({active: test.capture.active, exporting: test.capture.exporting,
                finishing: test.capture.finishing, sceneFocused: !!scene?.activeFocus, dragging: test.capture.dragging, closePending: test.capture.closePending, tool: test.capture.tool, selection: test.capture.selection, current: test.capture.current, cursor: test.capture.includeCursor, preferences: test.capture.preferences, frames: test.capture.firstFrames,
                recordPending: test.capture.recordPending, recording: test.capture.recording,
                editing: !!field?.visible, text: field?.text || "", strokes: view?.strokes || [],
                observerFocused: underlying.active, events: test.events,
                panel: test.desktop?.panel || "", captureActive: !!test.desktop?.captureActive,
                wantsGrab: !!test.desktop?.pill.wantsFocusGrab, query: search?.text || "",
                selected: test.desktop?.pill.activePane?.selectedId || ""});
        }
    }
}
