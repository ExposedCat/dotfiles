import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell

// Run through native-ui.py on the isolated desktop. No real polkit registration.
Scope {
    id: test
    property var app: null
    property int phase: 0
    property double started: Date.now()
    property int openingFrames: 0
    property int closingFrames: 0
    property real previousHeight: 40
    property bool previewCaptured: false
    TestResult { id: objects }
    QtObject { id: agent; property var flow: null }
    QtObject {
        id: flow
        property bool isCompleted: false
        property bool isResponseRequired: true
        property string message: "Authentication is required to override base OS software"
        property string inputPrompt: "Password:"
        property bool responseVisible: false
        property string supplementaryMessage: ""
        property bool supplementaryIsError: false
        property bool failed: false
        property var identities: [{name: "Fixture user"}]
        property var selectedIdentity: identities[0]
        property int submittedLength: 0
        property int cancelled: 0
        function submit(value) { submittedLength = value.length; isResponseRequired = false; }
        function cancelAuthenticationRequest() { cancelled++; isCompleted = true; }
    }
    function check(value, message) {
        if (!value) { console.error("AUTH FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function advance() { phase++; started = Date.now(); }
    function password() { return objects.findChild(app.pill.activePane || app.pill.authenticationPane, "authenticationPassword"); }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "Private fixture required");
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(component.status === Component.Ready, component.errorString());
        app = component.createObject(test);
        check(!!app, component.errorString());
        app.authentication.agent = agent;
    }
    Timer {
        interval: 16; running: !!test.app; repeat: true
        onTriggered: {
            const app = test.app, elapsed = Date.now() - test.started;
            const height = app.pill.pillGeometry.height;
            if (height !== test.previousHeight && height > 40 && height < app.pill.paneHeight) {
                if (app.panel === "authentication") test.openingFrames++;
                else test.closingFrames++;
            }
            test.previousHeight = height;
            if (test.phase === 1 && elapsed > 280 && !test.previewCaptured && Quickshell.env("DOTFILES_AUTH_PREVIEW")) {
                test.previewCaptured = true;
                objects.findChild(app.pill, "floatingPill").grabToImage(result => result.saveToFile(Quickshell.env("DOTFILES_AUTH_PREVIEW")));
            }
            if (test.phase === 0 && elapsed > 300) {
                test.check(height === 40, "Initial compact pill");
                agent.flow = flow;
                test.advance();
            } else if (test.phase === 1 && elapsed > 400) {
                test.check(app.panel === "authentication" && app.authentication.active, "Prompt must open in existing pill");
                test.check(height === app.pill.activePane.desiredHeight && test.openingFrames > 2, "Opening must morph through intermediate frames");
                test.check(!app.pill.wantsFocusGrab, "Exclusive authentication must not compete with the normal focus grab");
                app.pill.lostFocus();
                test.check(app.panel === "authentication" && flow.cancelled === 0, "Focus handoff must not cancel authentication");
                const description = objects.findChild(app.pill.activePane, "authenticationDescription");
                test.check(description.text === flow.message && description.x > 26, "Description must follow the shield");
                test.check(test.password().activeFocus && test.password().echoMode === TextInput.Password, "Masked input must get keyboard focus");
                test.password().text = "fixture-password";
                app.pill.activePane.submit();
                test.check(flow.submittedLength === 16 && test.password().text === "" && !test.password().enabled, "Submission must clear secret and await next challenge");
                test.advance();
            } else if (test.phase === 2 && elapsed > 100) {
                flow.supplementaryMessage = "Incorrect password. Try again.";
                flow.supplementaryIsError = true;
                flow.isResponseRequired = true;
                test.advance();
            } else if (test.phase === 3 && elapsed > 300) {
                test.check(test.password().activeFocus && test.password().text === "", "Retry must focus a cleared field");
                test.password().text = "discard-on-identity-change";
                flow.identities = [{name: "Fixture user"}, {name: "Administrator"}];
                flow.selectedIdentity = flow.identities[1];
                test.check(test.password().text === "", "Identity changes must clear secret");
                test.password().text = "discard-on-success";
                flow.isCompleted = true;
                test.check(app.panel === "" && test.password().text === "", "Completion must close and clear");
                test.advance();
            } else if (test.phase === 4 && elapsed > 400) {
                test.check(height === 40 && test.closingFrames > 2, "Closing must morph back into pill");
                agent.flow = null;
                flow.isCompleted = false;
                agent.flow = flow;
                test.advance();
            } else if (test.phase === 5 && elapsed > 350) {
                test.password().text = "discard-on-dismissal";
                app.pill.dismiss();
                test.check(flow.cancelled === 1 && test.password().text === "" && !app.authentication.active, "Dismissal cancels once and clears secret");
                test.advance();
            } else if (test.phase === 6 && elapsed > 350) {
                test.check(height === 40, "Cancelled prompt must collapse");
                console.warn("BACKEND UI PASS: authentication description, focus, masked submission, retry, identity switch, completion, cancellation, and opening/closing morph frames");
                Qt.quit();
            }
        }
    }
    Timer { interval: 10000; running: true; onTriggered: test.check(false, "Timed out at phase " + test.phase) }
}
