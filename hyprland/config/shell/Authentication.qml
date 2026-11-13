import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland

Scope {
    id: root
    required property var shell
    required property var theme
    property var agent: null
    readonly property var flow: agent ? agent.flow : null
    readonly property bool testing: shell.fixture && !!shell.fixtureData.auth
    readonly property bool active: testing || !!(flow && !flow.isCompleted)
    function submit() {
        const response = password.text;
        password.clear();
        if (testing) { shell.fixtureEvent("auth-submit", {length: response.length}); return }
        if (flow && flow.isResponseRequired) flow.submit(response);
    }
    function cancel() {
        password.clear();
        if (testing) { shell.fixtureEvent("auth-cancel", {}); return }
        if (flow) flow.cancelAuthenticationRequest();
    }
    onFlowChanged: { password.clear(); if (flow) focusDelay.restart() }
    onActiveChanged: { password.clear(); if (active) { shell.panel = ""; focusDelay.restart() } }
    Component { id: agentComponent; PolkitAgent {} }
    Component.onCompleted: { if (!shell.fixture) agent = agentComponent.createObject(root) }
    Connections {
        target: root.flow
        function onIsResponseRequiredChanged() { password.clear(); if (root.flow && root.flow.isResponseRequired) focusDelay.restart() }
    }
    Timer { id: focusDelay; interval: 60; onTriggered: password.forceActiveFocus() }
    PanelWindow {
        visible: root.active
        screen: root.shell.focusedScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: -1; color: "#66000000"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dotfiles-authentication"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        Rectangle {
            width: Math.min(480, parent.width - 40); height: content.implicitHeight + 44
            anchors.centerIn: parent
            radius: 16; color: root.theme.background; border.width: 1; border.color: root.theme.accent
            ColumnLayout {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
                spacing: 16
                RowLayout {
                    ShellIcon { name: "shield-check"; Layout.preferredWidth: 26; Layout.preferredHeight: 26 }
                    Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; text: "Authentication required"; color: root.theme.text }
                }
                Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; Layout.fillWidth: true; text: root.testing ? "Authentication is required to change system settings." : root.flow ? root.flow.message : ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: root.theme.text }
                ComboBox {
                    font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize
                    id: identity
                    Layout.fillWidth: true
                    visible: !root.testing && root.flow && root.flow.identities.length > 1
                    model: root.flow ? root.flow.identities : []
                    displayText: currentValue ? String(currentValue.name || currentValue.userName || currentValue.uid || currentValue) : ""
                    onActivated: { if (root.flow) root.flow.selectedIdentity = currentValue; password.clear() }
                }
                Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; text: root.testing ? "Password" : root.flow ? root.flow.inputPrompt : ""; color: root.theme.secondary; textFormat: Text.PlainText }
                TextField {
                    font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize
                    id: password
                    Layout.fillWidth: true; implicitHeight: 44
                    enabled: root.testing || !!(root.flow && root.flow.isResponseRequired)
                    echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                    color: root.theme.text; leftPadding: 12
                    selectByMouse: true
                    background: Rectangle { radius: 8; color: root.theme.surface; border.width: 1; border.color: password.activeFocus ? root.theme.accent : root.theme.border }
                    onAccepted: root.submit()
                    Keys.onEscapePressed: root.cancel()
                }
                Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; Layout.fillWidth: true; visible: text.length > 0; text: root.testing ? (root.shell.fixtureData.authError || "") : root.flow ? (root.flow.supplementaryMessage || (root.flow.failed ? "Authentication failed. Try again." : "")) : ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: root.flow && (root.flow.supplementaryIsError || root.flow.failed) ? root.theme.red : root.theme.secondary }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    ShellButton { theme: root.theme; text: "Cancel"; onClicked: root.cancel() }
                    ShellButton { theme: root.theme; text: "Authenticate"; selected: true; enabled: password.enabled; onClicked: root.submit() }
                }
            }
        }
        Shortcut { sequence: "Escape"; onActivated: root.cancel() }
    }
}
