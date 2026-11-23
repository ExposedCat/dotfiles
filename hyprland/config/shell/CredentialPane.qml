import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    required property var shell
    required property var theme
    readonly property var request: shell.credentials.data
    property var values: ({})
    property bool remember: true
    property Item hoveredControl: null
    property Item focusedControl: null
    property Item interactionControl: null
    readonly property bool vpn: request.networkType === "vpn"
    readonly property string heading: request.kind === "bluetooth" ? (request.subtitle || request.title || "Bluetooth device")
        : request.subtitle ? "Connect to " + request.subtitle : (request.title || "Connect to network")
    readonly property string headingIcon: request.kind === "bluetooth" ? "bluetooth" : vpn ? "shield-lock" : "wifi-lock"
    readonly property Item emberTarget: {
        if (!shell.credentials.active || shell.credentials.submitting) return null;
        const control = interactionControl || hoveredControl || focusedControl;
        if (control && control.visible && control.enabled) return control.emberSlot;
        return confirm.visible && confirm.enabled ? confirm.emberSlot : null;
    }
    function trackHover(control, entered) {
        if (entered) { hoveredControl = control; interactionControl = control; }
        else {
            if (hoveredControl === control) hoveredControl = null;
            if (interactionControl === control) interactionControl = focusedControl || hoveredControl;
        }
    }
    function trackFocus(control, focused) {
        if (focused) { focusedControl = control; interactionControl = control; }
        else {
            if (focusedControl === control) focusedControl = null;
            if (interactionControl === control) interactionControl = hoveredControl || focusedControl;
        }
    }
    readonly property real desiredWidth: 460
    readonly property real desiredHeight: Math.min(700, content.implicitHeight + 40)
    readonly property bool canAccept: !request.displayOnly && (request.fields || []).every(field => {
        const value = values[field.key] || "";
        return value.length >= (field.minLength || 1) && value.length <= (field.maxLength || 4096)
            && (field.validation !== "digits" || /^[0-9]+$/.test(value));
    })
    function activate() {
        hoveredControl = null; focusedControl = null; interactionControl = null;
        const next = {};
        for (const field of request.fields || []) next[field.key] = field.secret ? "" : (field.value || "");
        values = next; remember = true;
        for (let i = 0; i < fields.count; ++i) if (fields.itemAt(i)) fields.itemAt(i).reset();
        Qt.callLater(focusSearch);
    }
    function focusSearch() {
        if (fields.count && fields.itemAt(0)) fields.itemAt(0).focusInput();
        // Opening a fieldless prompt should not make Cancel look selected.
        // Buttons still show the shared focus outline when reached with Tab.
        else root.forceActiveFocus();
    }
    function accept() {
        if (canAccept) shell.credentials.finish({response: 0, values: values, remember: remember});
    }
    function setInput(index, value) { if (fields.itemAt(index)) fields.itemAt(index).setInput(value); }
    function inputPoint(index) { return fields.itemAt(index).inputPoint(); }
    function inputRevealed(index) { return fields.itemAt(index).revealed; }
    function controlPoint(name, index) {
        if (name === "input") return inputPoint(index || 0);
        if (name === "visibility") return fields.itemAt(index || 0).visibilityPoint();
        const button = name === "cancel" ? cancel : name === "connect" ? confirm : close;
        return button.mapToGlobal(button.width / 2, button.height / 2);
    }
    function clear() {
        hoveredControl = null; focusedControl = null; interactionControl = null;
        values = {};
        for (let i = 0; i < fields.count; ++i) if (fields.itemAt(i)) fields.itemAt(i).clear();
    }
    Connections { target: root.shell.credentials; function onCleared() { root.clear() } function onDataChanged() { if (root.shell.credentials.active && !root.shell.credentials.submitting) Qt.callLater(root.activate) } }
    enabled: !shell.credentials.submitting
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 18
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            ShellIcon { name: root.headingIcon; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
            Text { Layout.fillWidth: true; text: root.heading; textFormat: Text.PlainText; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; font.weight: Font.DemiBold; wrapMode: Text.Wrap }
            ShellButton {
                id: close; theme: root.theme; emberShell: root.shell
                icon: "x"; hint: "Cancel"; implicitWidth: 30; implicitHeight: 30
                emberSlot.objectName: "credential-close"
                onHoveredChanged: root.trackHover(this, hovered)
                onActiveFocusChanged: root.trackFocus(this, activeFocus)
                onClicked: root.shell.credentials.finish({response: 1})
            }
        }
        Text { visible: text.length > 0; Layout.fillWidth: true; text: root.request.body || ""; textFormat: Text.PlainText; color: root.theme.secondary; font: root.theme.textFont; wrapMode: Text.Wrap }
        Rectangle {
            visible: !!root.request.code; Layout.fillWidth: true; implicitHeight: 86; radius: 14; color: root.theme.background
            Text { anchors.centerIn: parent; text: (root.request.code || "").split("").join("  "); color: root.theme.text; font.family: "monospace"; font.pixelSize: 30; font.weight: Font.DemiBold }
            Rectangle { visible: !!root.request.displayOnly; anchors { bottom: parent.bottom; left: parent.left; margins: 8 } width: (parent.width - 16) * Math.min(6, root.request.entered || 0) / 6; height: 3; radius: 2; color: "#cc7855"; Behavior on width { NumberAnimation { duration: 120 } } }
        }
        Repeater {
            id: fields
            model: root.request.fields || []
            delegate: ColumnLayout {
                id: fieldRow
                required property var modelData
                required property int index
                Layout.fillWidth: true; spacing: 8
                function focusInput() { input.forceActiveFocus() }
                function setInput(value) { input.text = value }
                function inputPoint() { return input.mapToGlobal(input.width / 2, input.height / 2) }
                function visibilityPoint() { return visibilityButton.mapToGlobal(visibilityButton.width / 2, visibilityButton.height / 2) }
                function clear() { input.clear(); revealed = false }
                function reset() { input.text = modelData.secret ? "" : (modelData.value || ""); revealed = false }
                property bool revealed: false
                Text { text: fieldRow.modelData.label; textFormat: Text.PlainText; color: root.theme.secondary; font: root.theme.textFont }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    TextField {
                        id: input; objectName: "credentialInput" + fieldRow.index
                        property alias emberSlot: inputCaret
                        Layout.fillWidth: true; implicitHeight: 44; font: root.theme.textFont
                        color: root.theme.text; leftPadding: 12; rightPadding: 12
                        maximumLength: fieldRow.modelData.maxLength || 4096
                        passwordCharacter: "•"
                        echoMode: fieldRow.modelData.secret && !fieldRow.revealed ? TextInput.Password : TextInput.Normal
                        inputMethodHints: fieldRow.modelData.secret ? Qt.ImhHiddenText | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData : Qt.ImhNone
                        selectByMouse: true
                        hoverEnabled: true
                        cursorVisible: !root.shell.emberEnabled
                        // TextInput changes cursorVisible internally during editing.
                        // Keep its delegate hidden while the shared ember is the caret.
                        cursorDelegate: Rectangle { visible: !root.shell.emberEnabled; width: 1; color: root.theme.focusColor }
                        onHoveredChanged: root.trackHover(this, hovered)
                        onActiveFocusChanged: root.trackFocus(this, activeFocus)
                        onTextEdited: root.trackFocus(this, true)
                        EmberSlot {
                            id: inputCaret; shell: root.shell
                            objectName: "credential-input-" + fieldRow.index
                            x: input.cursorRectangle.x; y: input.cursorRectangle.y
                            width: 3; height: input.cursorRectangle.height || 19
                            shapeRadius: 1.5; caret: true
                        }
                        background: Rectangle {
                            radius: 10; color: fieldRow.modelData.secret ? root.theme.background : root.theme.surface
                            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 } height: 2; radius: 1; visible: input.activeFocus && !root.shell.emberEnabled; color: root.theme.focusColor }
                        }
                        onTextChanged: { const next = Object.assign({}, root.values); next[fieldRow.modelData.key] = text; root.values = next }
                        onAccepted: { if (fieldRow.index + 1 < fields.count) fields.itemAt(fieldRow.index + 1).focusInput(); else root.accept() }
                        Component.onCompleted: fieldRow.reset()
                    }
                    ShellButton {
                        id: visibilityButton
                        visible: !!fieldRow.modelData.secret; theme: root.theme; emberShell: root.shell
                        icon: fieldRow.revealed ? "eye-off" : "eye"
                        hint: fieldRow.revealed ? "Hide password" : "Show password"
                        Accessible.checkable: true; Accessible.checked: fieldRow.revealed
                        implicitHeight: 40; implicitWidth: 40; radius: 10
                        emberSlot.objectName: "credential-visibility-" + fieldRow.index
                        onHoveredChanged: root.trackHover(this, hovered)
                        onActiveFocusChanged: root.trackFocus(this, activeFocus)
                        onClicked: { forceActiveFocus(Qt.MouseFocusReason); fieldRow.revealed = !fieldRow.revealed; }
                    }
                }
            }
        }
        PortalCheckBox {
            id: rememberBox
            theme: root.theme; emberShell: root.shell
            emberSlot.objectName: "credential-remember"
            visible: !!root.request.rememberAllowed; checked: root.remember
            text: "Remember in keyring"; onToggled: root.remember = checked
            onHoveredChanged: root.trackHover(this, hovered)
            onActiveFocusChanged: root.trackFocus(this, activeFocus)
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            Text { visible: !!root.request.displayOnly; Layout.fillWidth: true; text: "Waiting for your device…"; color: root.theme.secondary; font: root.theme.textFont }
            Item { visible: !root.request.displayOnly; Layout.fillWidth: true }
            ShellButton {
                id: cancel; theme: root.theme; emberShell: root.shell; text: "Cancel"; implicitHeight: 40
                emberSlot.objectName: "credential-cancel"
                onHoveredChanged: root.trackHover(this, hovered)
                onActiveFocusChanged: root.trackFocus(this, activeFocus)
                onClicked: root.shell.credentials.finish({response: 1})
            }
            ShellButton {
                id: confirm; visible: !root.request.displayOnly; theme: root.theme; emberShell: root.shell
                text: root.request.confirmLabel || "Continue"; selected: true; implicitHeight: 40; enabled: root.canAccept
                emberSlot.objectName: "credential-connect"
                onHoveredChanged: root.trackHover(this, hovered)
                onActiveFocusChanged: root.trackFocus(this, activeFocus)
                onClicked: root.accept()
            }
        }
    }
    Component.onCompleted: activate()
    Component.onDestruction: clear()
}
