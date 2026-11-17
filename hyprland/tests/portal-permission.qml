import QtQuick
import QtQuick.Window
import QtTest
import Quickshell

// Run through isolated-gui. This uses sample data and never requests permission.
Scope {
    id: test
    property var dialog: null
    property int phase: 0
    property var replies: []
    readonly property var request: ({
        fixture: true, kind: "access", app: {name: "Prompt Gallery"}, title: "Allow microphone access?",
        subtitle: "This application would like to use your microphone.",
        body: "Your microphone will be available to this application. You can stop recording at any time.",
        choices: [{id: "remember", name: "Remember my decision", values: [], selected: "false"}]
    })
    TestResult { id: objects }
    TestCase { id: input; when: false }
    function check(value, message) {
        if (!value) { console.error("PERMISSION FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    Window {
        id: window
        visible: true; width: test.dialog ? test.dialog.desiredWidth : 440; height: test.dialog ? test.dialog.desiredHeight : 240
        title: "Permission portal fixture"; color: "#202020"
        Item { id: surface; anchors.fill: parent }
    }
    Component.onCompleted: {
        const source = "file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/";
        const theme = Qt.createComponent(source + "PillTheme.qml").createObject(test);
        Qt.createComponent(source + "PillBackground.qml").createObject(surface, {width: Qt.binding(() => window.width), height: Qt.binding(() => window.height), theme: theme});
        const component = Qt.createComponent(source + "PortalDialog.qml");
        check(component.status === Component.Ready, component.errorString());
        dialog = component.createObject(surface, {
            x: 12, y: 8, width: Qt.binding(() => window.width - 24), height: Qt.binding(() => window.height - 20), theme: theme, requestData: request
        });
        check(!!dialog, component.errorString());
        dialog.responded.connect(response => test.replies.push(response));
        dialog.activate();
    }
    Timer {
        interval: 400; repeat: true; running: !!test.dialog
        onTriggered: {
            const dialog = test.dialog;
            if (test.phase === 0) {
                const heading = objects.findChild(dialog, "permissionHeading");
                const description = objects.findChild(dialog, "permissionDescription");
                const remember = objects.findChild(dialog, "portalRemember");
                test.check(heading.text === "Allow Prompt Gallery microphone access?", "App must be in the permission question");
                test.check(description.visible && description.text.includes(test.request.body), "Description must always be visible");
                test.check(remember.visible && remember.text === "Remember", "Remember must have the short label");
                const footer = remember.mapToItem(dialog, 0, 0);
                const body = description.mapToItem(dialog, 0, description.height);
                test.check(footer.x === 0 && footer.y > body.y && footer.y + remember.height <= dialog.height, "Remember must sit at the bottom left");
                if (Quickshell.env("DOTFILES_PREVIEW_DIR")) surface.grabToImage(result => result.saveToFile(Quickshell.env("DOTFILES_PREVIEW_DIR") + "/permission.png"));
                input.mouseClick(remember, remember.width / 2, remember.height / 2);
                test.check(remember.checked, "Remember must toggle with the mouse");
                dialog.decide(0); dialog.decide(1);
                test.check(test.replies[0].choices.remember === "true" && test.replies[1].response === 1, "Remember must keep its supplied choice ID in allow/deny responses");
                test.check(dialog.permissionTitle({app: {name: "Photo Booth"}, title: "Allow camera access?"}) === "Allow Photo Booth camera access?", "Camera question");
                test.check(dialog.permissionTitle({app: {name: "Camera"}, title: "Allow camera access?"}) === "Allow Camera camera access?", "Resource name must not be mistaken for the app");
                test.check(dialog.permissionTitle({app: {name: "Prompt Gallery"}, title: "Allow Prompt Gallery microphone access?"}) === "Allow Prompt Gallery microphone access?", "Already attributed title must not repeat app name");
                test.check(dialog.permissionTitle({app: {name: "Test"}, title: "Mikrofonzugriff erlauben?"}) === "Test: Mikrofonzugriff erlauben?", "Other wording must remain intact");
                test.check(dialog.permissionTitle({title: "A custom permission question"}) === "A custom permission question", "Unknown app must not be invented");
            } else if (test.phase === 1) {
                dialog.requestData = Object.assign({}, test.request, {choices: [{id: "notifications", name: "Notify me", values: [], selected: "true"}]});
                dialog.activate();
            } else if (test.phase === 2) {
                test.check(!objects.findChild(dialog, "portalRemember").visible, "A remember choice must not be invented");
                dialog.decide(0);
                test.check(test.replies[2].choices.notifications === "true", "Unrelated choices must keep their ID and value");
                dialog.requestData = Object.assign({}, test.request, {app: {name: "An application with a very long name that must wrap across the question"}, body: test.request.body.repeat(12)});
                dialog.activate();
            } else if (test.phase === 3) {
                const remember = objects.findChild(dialog, "portalRemember");
                test.check(dialog.desiredHeight <= 620 && remember.mapToItem(dialog, 0, remember.height).y <= dialog.height, "Long descriptions must scroll above the footer");
                if (Quickshell.env("DOTFILES_PREVIEW_DIR")) surface.grabToImage(result => result.saveToFile(Quickshell.env("DOTFILES_PREVIEW_DIR") + "/long-permission.png"));
            } else if (test.phase === 4) {
                dialog.requestData = {fixture: true, kind: "share", outputs: [{id: "screen:preview", name: "Preview screen", subtitle: "1920 × 1080", kind: "screen", width: 1920, height: 1080}], windows: [], workspaces: []};
                dialog.activate(); dialog.choose("screen:preview");
            } else if (test.phase === 5) {
                const remember = objects.findChild(dialog, "portalRemember");
                test.check(remember.visible && !remember.checked, "Sharing must keep its own Remember state");
                input.mouseClick(remember, remember.width / 2, remember.height / 2);
                dialog.decide(0);
                test.check(test.replies[3].remember === true && test.replies[3].choice === "screen:preview", "Sharing Remember must keep its existing response contract");
            } else {
                console.warn("BACKEND UI PASS: attributed permission titles, visible description, Remember footer, long-content layout, and preserved permission/sharing responses");
                Qt.quit();
            }
            test.phase++;
        }
    }
    Timer { interval: 10000; running: true; onTriggered: test.check(false, "Permission fixture timed out") }
}
