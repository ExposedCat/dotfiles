import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    required property var shell
    required property var theme
    readonly property var authentication: shell.authentication
    readonly property var flow: authentication.flow
    readonly property real desiredWidth: 480
    readonly property real desiredHeight: content.implicitHeight + 40
    property Item interactionControl: password
    readonly property Item emberTarget: authentication.active && interactionControl?.enabled ? interactionControl.emberSlot : null
    function activate() { password.clear(); Qt.callLater(focusSearch); }
    function focusSearch() { if (shell.panel === "authentication" && password.enabled) password.forceActiveFocus(); }
    function submit() {
        const response = password.text;
        password.clear();
        authentication.submit(response);
    }
    Connections {
        target: root.authentication
        function onCleared() { password.clear(); }
        function onFocusRequested() { Qt.callLater(root.focusSearch); }
    }
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 16
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            ShellIcon { name: "shield-check"; Layout.preferredWidth: 26; Layout.preferredHeight: 26; Layout.alignment: Qt.AlignTop }
            Text {
                objectName: "authenticationDescription"
                Layout.fillWidth: true; font: root.theme.textFont; text: root.authentication.message
                textFormat: Text.PlainText; wrapMode: Text.Wrap; color: root.theme.text
            }
        }
        PillComboBox {
            id: identity
            theme: root.theme; Layout.fillWidth: true
            visible: !root.authentication.testing && root.flow && root.flow.identities.length > 1
            model: root.flow ? root.flow.identities : []
            currentIndex: root.flow ? root.flow.identities.indexOf(root.flow.selectedIdentity) : -1
            optionLabel: value => value ? String(value.name || value.userName || value.uid || value) : ""
            displayText: optionLabel(currentValue)
            onActivated: { if (root.flow) root.flow.selectedIdentity = currentValue; password.clear(); Qt.callLater(root.focusSearch); }
        }
        Text { font: root.theme.textFont; text: root.authentication.inputPrompt; color: root.theme.secondary; textFormat: Text.PlainText }
        TextField {
            id: password; objectName: "authenticationPassword"
            property alias emberSlot: inputCaret
            font: root.theme.textFont; Layout.fillWidth: true; implicitHeight: 44
            enabled: root.authentication.active && (root.authentication.testing || !!(root.flow && root.flow.isResponseRequired))
            echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
            inputMethodHints: echoMode === TextInput.Password ? Qt.ImhHiddenText | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData : Qt.ImhNone
            passwordCharacter: "•"; color: root.theme.text; leftPadding: 12; rightPadding: 12
            selectByMouse: true; hoverEnabled: true
            cursorDelegate: Rectangle { visible: !root.shell.emberEnabled; width: 1; color: root.theme.focusColor }
            onHoveredChanged: { if (hovered) root.interactionControl = password; }
            onActiveFocusChanged: { if (activeFocus) root.interactionControl = password; }
            onTextEdited: root.interactionControl = password
            EmberSlot {
                id: inputCaret; shell: root.shell; objectName: "authentication-input"
                x: password.cursorRectangle.x; y: password.cursorRectangle.y
                width: 3; height: password.cursorRectangle.height || 19; shapeRadius: 1.5; caret: true
            }
            background: Rectangle {
                radius: 10; color: root.theme.surface
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 } height: 2; radius: 1; color: root.theme.focusColor; visible: password.activeFocus && !root.shell.emberEnabled }
            }
            onAccepted: root.submit()
        }
        Text {
            font: root.theme.textFont; Layout.fillWidth: true; visible: text.length > 0
            text: root.authentication.testing ? (root.shell.fixtureData.authError || "") : root.flow ? (root.flow.supplementaryMessage || (root.flow.failed ? "Authentication failed. Try again." : "")) : ""
            textFormat: Text.PlainText; wrapMode: Text.Wrap
            color: root.flow && (root.flow.supplementaryIsError || root.flow.failed) ? root.theme.red : root.theme.secondary
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ShellButton {
                id: cancel; theme: root.theme; emberShell: root.shell; text: "Cancel"
                emberSlot.objectName: "authentication-cancel"
                onHoveredChanged: { if (hovered) root.interactionControl = cancel; }
                onActiveFocusChanged: { if (activeFocus) root.interactionControl = cancel; }
                onClicked: root.authentication.cancel()
            }
            ShellButton {
                id: confirm; theme: root.theme; emberShell: root.shell; text: "Authenticate"; selected: true; enabled: password.enabled
                emberSlot.objectName: "authentication-confirm"
                onHoveredChanged: { if (hovered) root.interactionControl = confirm; }
                onActiveFocusChanged: { if (activeFocus) root.interactionControl = confirm; }
                onClicked: root.submit()
            }
        }
    }
    Component.onDestruction: password.clear()
}
