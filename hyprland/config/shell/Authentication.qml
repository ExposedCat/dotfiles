import QtQuick
import Quickshell
import Quickshell.Services.Polkit

Scope {
    id: root
    required property var shell
    property var agent: null
    readonly property var flow: agent ? agent.flow : null
    readonly property bool testing: shell.fixture && !!shell.fixtureData.auth
    property bool cancelling: false
    readonly property bool active: !cancelling && (testing || !!(flow && !flow.isCompleted))
    // Keep the last public prompt while the pill animates closed.
    property string message: ""
    property string inputPrompt: ""
    signal cleared()
    signal focusRequested()
    function updatePrompt() {
        if (testing) {
            message = "Authentication is required to change system settings.";
            inputPrompt = "Password";
        } else if (flow) {
            message = flow.message;
            inputPrompt = flow.inputPrompt;
        }
    }
    function submit(response) {
        if (!active) return;
        if (testing) { shell.fixtureEvent("auth-submit", {length: response.length}); return; }
        if (flow && flow.isResponseRequired) flow.submit(response);
    }
    function cancel() {
        if (!active) return;
        cancelling = true;
        cleared();
        if (testing) shell.fixtureEvent("auth-cancel", {});
        else if (flow) flow.cancelAuthenticationRequest();
    }
    function sync() {
        cleared();
        updatePrompt();
        if (active) {
            shell.pillHidden = false;
            shell.panel = "authentication";
            focusRequested();
        } else if (shell.panel === "authentication") shell.panel = "";
    }
    onFlowChanged: { cancelling = false; sync(); }
    onTestingChanged: { cancelling = false; sync(); }
    onActiveChanged: sync()
    Component { id: agentComponent; PolkitAgent {} }
    Component.onCompleted: { if (!shell.fixture) agent = agentComponent.createObject(root); sync(); }
    Connections {
        target: root.flow
        function onIsResponseRequiredChanged() { root.cleared(); root.updatePrompt(); if (root.flow && root.flow.isResponseRequired) root.focusRequested(); }
        function onSelectedIdentityChanged() { root.cleared(); root.focusRequested(); }
        function onInputPromptChanged() { root.updatePrompt(); }
    }
    Connections {
        target: root.shell
        function onPanelChanged() { if (root.active && root.shell.panel !== "authentication") root.cancel(); }
    }
}
