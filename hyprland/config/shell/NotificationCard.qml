import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var theme
    required property var store
    required property var entry
    property bool inCenter: false
    property var emberShell: null
    property alias emberSlot: unreadSlot
    property Item hoveredAction: null
    property Item focusedAction: null
    readonly property Item emberTarget: (hoveredAction || focusedAction)?.emberSlot || unreadSlot
    function followAction(button, inside, keyboard) {
        if (keyboard) { if (inside) focusedAction = button; else if (focusedAction === button) focusedAction = null; }
        else { if (inside) hoveredAction = button; else if (hoveredAction === button) hoveredAction = null; }
    }
    readonly property bool hovered: cardHover.hovered
    readonly property bool containsFocus: {
        let item = root.Window.window ? root.Window.window.activeFocusItem : null;
        while (item) { if (item === root) return true; item = item.parent; }
        return false;
    }
    EmberSlot { id: unreadSlot; shell: root.emberShell; x: 8; y: 14; width: 3; height: Math.max(4, parent.height - 28); shapeRadius: 1.5 }
    property bool embedded: false
    property bool groupControls: false
    property bool groupExpanded: false
    property string groupKey: ""
    signal toggleGroup()
    property bool geometryReady: false
    property bool actionsExpanded: false
    property bool hoverExpansionAllowed: true
    onHoverExpansionAllowedChanged: { if (hoverExpansionAllowed) actionsExpanded = cardHover.hovered || composing || containsFocus; }
    readonly property var notification: store.live[entry.id] || null
    readonly property bool canActivate: !!notification && notification.actions.some(a => a.identifier === "default")
    readonly property bool canReply: !!notification && notification.hasInlineReply
    readonly property bool hasActions: !!notification && notification.actions.some(a => a.identifier !== "default" && a.identifier !== "inline-reply")
    readonly property bool composing: canReply && !!store.replying[entry.id]
    function sendReply() { store.sendReply(entry.id) }
    readonly property bool removing: !!(store.removing && store.removing[entry.id])
    property real appearance: 0
    property real groupReveal: 1
    Component.onCompleted: appearance = 1
    opacity: inCenter ? (removing ? 0 : appearance * groupReveal) : 1
    Behavior on opacity { enabled: root.inCenter && root.removing; NumberAnimation { duration: 120 } }
    implicitHeight: inCenter && removing ? 0 : content.implicitHeight + 26
    Behavior on implicitHeight { enabled: root.geometryReady; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
    Rectangle {
        visible: !root.embedded
        anchors.fill: parent; z: -1
        radius: 12; color: root.theme.surface
        border.width: root.entry.critical ? 1 : 0; border.color: root.theme.red
    }
    Connections {
        enabled: !root.geometryReady
        target: root.Window.window
        function onFrameSwapped() { root.geometryReady = true }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.canActivate
        cursorShape: Qt.PointingHandCursor
        onClicked: root.store.invoke(root.entry.id, "default")
    }
    HoverHandler {
        id: cardHover
        onHoveredChanged: {
            if (hovered) {
                hoverExit.stop();
                if (root.hoverExpansionAllowed) root.actionsExpanded = true;
                if (!root.inCenter) root.store.hoverPopup(root.entry.id, true);
            } else hoverExit.restart();
        }
    }
    Timer {
        id: hoverExit; interval: 80
        onTriggered: {
            if (cardHover.hovered || root.composing || !root.hoverExpansionAllowed) return;
            root.actionsExpanded = false;
            if (!root.inCenter) root.store.hoverPopup(root.entry.id, false);
        }
    }
    onComposingChanged: {
        if (composing) { hoverExit.stop(); actionsExpanded = true }
        else if (!cardHover.hovered) hoverExit.restart();
    }
    Item {
        anchors.fill: parent
        clip: true
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 13 }
        spacing: 10
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            Image {
                source: root.entry.image || ""
                visible: source.toString().length > 0 && status !== Image.Error
                Layout.preferredWidth: 56; Layout.preferredHeight: 56
                Layout.alignment: Qt.AlignTop
                sourceSize.width: 112; sourceSize.height: 112
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 5
                RowLayout {
                    Layout.fillWidth: true; spacing: 7
                    Image {
                        source: root.entry.icon ? (/^(file:|image:|\/)/.test(root.entry.icon) ? root.entry.icon : Quickshell.iconPath(root.entry.icon, true)) : Quickshell.iconPath("application-x-executable", true)
                        visible: source.toString().length > 0 && status !== Image.Error
                        Layout.preferredWidth: 18; Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignTop; Layout.topMargin: 3
                        sourceSize.width: 18; sourceSize.height: 18
                    }
                    Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; Layout.fillWidth: true; text: root.entry.summary; textFormat: Text.PlainText; color: root.theme.text; wrapMode: Text.NoWrap; maximumLineCount: 1; elide: Text.ElideRight }
                    ShellButton { visible: root.groupControls; theme: root.theme; icon: root.groupExpanded ? "chevron-up" : "chevron-down"; hint: root.groupExpanded ? "Collapse notifications" : "Expand notifications"; implicitWidth: 30; implicitHeight: 30; Layout.alignment: Qt.AlignTop; onClicked: root.toggleGroup() }
                    ShellButton { theme: root.theme; icon: "x"; hint: root.groupControls ? "Dismiss group" : "Dismiss notification"; opacity: root.groupControls || root.actionsExpanded || root.composing || activeFocus ? 1 : 0; enabled: opacity > 0; implicitWidth: 30; implicitHeight: 30; Layout.alignment: Qt.AlignTop; onClicked: root.groupControls ? root.store.removeGroup(root.groupKey) : root.store.remove(root.entry.id) }
                }
                Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; visible: text.length > 0; Layout.fillWidth: true; text: root.entry.body; textFormat: Text.PlainText; color: root.theme.text; wrapMode: Text.Wrap; maximumLineCount: root.actionsExpanded || root.composing || root.containsFocus ? 2147483647 : 1; elide: Text.ElideRight }
            }
        }
        Item {
            id: actionReveal
            objectName: "notificationActionReveal"
            Layout.fillWidth: true
            property real reveal: (root.actionsExpanded || root.composing || root.containsFocus) && (root.hasActions || (root.canReply && !root.composing)) ? 1 : 0
            Layout.topMargin: -content.spacing * (1 - reveal)
            Layout.preferredHeight: actions.implicitHeight * reveal
            implicitHeight: actions.implicitHeight * reveal
            clip: true
            Flow {
                id: actions
                width: parent.width
                opacity: actionReveal.reveal
                enabled: actionReveal.reveal > 0.9
                spacing: 6
                Repeater {
                    model: root.notification ? root.notification.actions.filter(a => a.identifier !== "default" && a.identifier !== "inline-reply") : []
                    ShellButton {
                        required property var modelData
                        emberShell: root.emberShell
                        onHoveredChanged: root.followAction(this, hovered, false)
                        onActiveFocusChanged: root.followAction(this, activeFocus, true)
                        theme: root.theme; text: modelData.text; selected: true
                        color: emberSlot.occupied ? "transparent" : root.theme.hover
                        onClicked: root.store.invoke(root.entry.id, modelData.identifier)
                    }
                }
                ShellButton {
                    emberShell: root.emberShell
                    onHoveredChanged: root.followAction(this, hovered, false)
                    onActiveFocusChanged: root.followAction(this, activeFocus, true)
                    theme: root.theme; text: "Reply"; selected: true
                    color: emberSlot.occupied ? "transparent" : root.theme.hover
                    visible: root.canReply && !root.composing
                    onClicked: { root.store.startReply(root.entry.id, root.inCenter ? "center" : "banner"); Qt.callLater(() => replyText.forceActiveFocus()) }
                }
            }
        }
        ColumnLayout {
            visible: root.composing
            Layout.fillWidth: true; spacing: 8
            TextField {
                font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize
                id: replyText
                Layout.fillWidth: true; implicitHeight: 38
                color: root.theme.text; leftPadding: 10
                placeholderText: root.notification ? (root.notification.inlineReplyPlaceholder || "Reply…") : "Reply…"
                placeholderTextColor: root.theme.secondary
                text: root.store.drafts[root.entry.id] || ""
                selectByMouse: true
                background: Rectangle { color: root.theme.background; radius: 8; border.width: 1; border.color: replyText.activeFocus ? root.theme.accent : root.theme.border }
                onTextEdited: root.store.setDraft(root.entry.id, text)
                onAccepted: root.sendReply()
                TapHandler { onTapped: root.store.startReply(root.entry.id, root.inCenter ? "center" : "banner") }
                Keys.onEscapePressed: event => { event.accepted = true; root.store.cancelReply(root.entry.id) }
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ShellButton { emberShell: root.emberShell; onHoveredChanged: root.followAction(this, hovered, false); onActiveFocusChanged: root.followAction(this, activeFocus, true); theme: root.theme; text: "Cancel"; onClicked: root.store.cancelReply(root.entry.id) }
                ShellButton { emberShell: root.emberShell; onHoveredChanged: root.followAction(this, hovered, false); onActiveFocusChanged: root.followAction(this, activeFocus, true); theme: root.theme; text: "Send"; selected: true; enabled: !!(root.store.drafts[root.entry.id] || "").trim(); onClicked: root.sendReply() }
            }
        }
    }
    }
}
