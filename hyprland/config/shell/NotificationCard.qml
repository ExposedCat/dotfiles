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
    EmberSlot { id: unreadSlot; shell: root.emberShell; x: 4; y: 12; width: 3; height: Math.max(4, parent.height - 24); shapeRadius: 1.5 }
    property bool embedded: false
    readonly property bool isBanner: !inCenter && !embedded
    property bool groupControls: false
    property bool groupExpanded: false
    property int groupCount: 1
    property bool manageHover: true
    signal toggleGroup()
    signal dismissGroup()
    property bool geometryReady: false
    property bool actionsExpanded: false
    readonly property bool detailsExpanded: inCenter || actionsExpanded || composing || containsFocus
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
    property real arrival: 1
    property real groupReveal: 1
    property real groupOffset: 0
    property bool retiring: false
    property real dismissProgress: 0
    property real heldHeight: 0
    property real layoutHeight: 0
    property real exitReveal: 1
    property real exitOffset: 0
    signal retired()
    function beginDismissal() {
        if (retiring) return;
        heldHeight = Math.max(1, height);
        layoutHeight = heldHeight;
        exitReveal = groupReveal;
        exitOffset = groupOffset;
        retiring = true;
        dismissal.restart();
    }
    function cancelDismissal() {
        dismissal.stop();
        retiring = false; dismissProgress = 0; heldHeight = 0;
    }
    Component.onCompleted: appearance = 1
    opacity: inCenter ? appearance * arrival * (retiring ? exitReveal * (1 - dismissProgress) : groupReveal) : 1
    transform: [
        Translate { y: (root.retiring ? root.exitOffset : root.groupOffset) - 24 * root.dismissProgress - 24 * (1 - root.arrival) },
        Rotation { origin.x: root.width * 0.7; origin.y: 0; angle: -3 * (1 - root.arrival) }
    ]
    implicitHeight: retiring ? layoutHeight : content.implicitHeight + 24
    Behavior on implicitHeight { enabled: root.geometryReady && !root.inCenter; NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
    SequentialAnimation {
        id: dismissal
        NumberAnimation { target: root; property: "dismissProgress"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "layoutHeight"; to: 0; duration: 160; easing.type: Easing.InOutCubic }
        onFinished: root.retired()
    }
    NotificationSurface {
        visible: !root.embedded
        anchors.fill: parent; z: -1
        theme: root.theme; inset: root.inCenter; critical: !!root.entry.critical
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
                if (!root.inCenter && root.hoverExpansionAllowed) root.actionsExpanded = true;
                if (!root.inCenter && root.manageHover) root.store.hoverPopup(root.entry.id, true);
            } else hoverExit.restart();
        }
    }
    Timer {
        id: hoverExit; interval: 80
        onTriggered: {
            if (cardHover.hovered || !root.hoverExpansionAllowed) return;
            // Retain the expanded pixels while a hovered banner slides away.
            if (!root.inCenter && root.manageHover) root.store.hoverPopup(root.entry.id, false);
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
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14; topMargin: 12 }
        spacing: 8
        RowLayout {
            Layout.fillWidth: true; spacing: 10
            SystemImage {
                objectName: "notificationImage"
                iconSource: root.entry.image || ""
                symbolicColor: root.theme.text
                Layout.preferredWidth: root.inCenter ? 40 : root.isBanner ? 56 : 48
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: root.inCenter || root.isBanner ? Qt.AlignVCenter : Qt.AlignTop
                sourceSize.width: 112; sourceSize.height: 112
                fillMode: iconSource.startsWith("image://icon/") ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                // The 30px dismiss control adds headroom above a two-line banner's title.
                transform: Translate { y: root.isBanner && body.visible ? -3 : 0 }
                RowLayout {
                    Layout.fillWidth: true; spacing: 7
                    Text { font: root.theme.textFont; Layout.fillWidth: true; text: root.entry.summary; textFormat: Text.PlainText; color: root.theme.text; wrapMode: Text.NoWrap; maximumLineCount: 1; elide: Text.ElideRight }
                    ShellButton { objectName: "notificationGroupToggle"; visible: root.groupControls; theme: root.theme; icon: root.groupExpanded ? "chevron-up" : "chevron-down"; hint: root.groupExpanded ? "Collapse notifications" : "Expand notifications"; implicitWidth: 30; implicitHeight: 30; Layout.alignment: Qt.AlignTop; onClicked: root.toggleGroup() }
                    NotificationDismiss {
                        objectName: "notificationDismiss"
                        theme: root.theme
                        hint: root.groupControls && !root.inCenter ? "Dismiss group" : "Dismiss notification"
                        grouped: root.inCenter && root.groupCount > 1
                        opacity: root.inCenter || root.groupControls || root.actionsExpanded || root.composing || activeFocus ? 1 : 0
                        enabled: opacity > 0 && !root.removing
                        Layout.alignment: Qt.AlignTop
                        onClicked: root.groupControls && !root.inCenter ? root.dismissGroup() : root.store.remove(root.entry.id)
                        onGroupDismissed: root.dismissGroup()
                    }
                }
                Text { id: body; objectName: "notificationBody"; font: root.theme.textFont; visible: text.length > 0; Layout.fillWidth: true; text: root.entry.body; textFormat: Text.PlainText; color: root.theme.secondary; wrapMode: Text.Wrap; maximumLineCount: root.detailsExpanded ? 5 : 1; elide: Text.ElideRight }
            }
        }
        Item {
            id: actionReveal
            objectName: "notificationActionReveal"
            Layout.fillWidth: true
            property real reveal: root.detailsExpanded && (root.hasActions || (root.canReply && !root.composing)) ? 1 : 0
            visible: !root.isBanner || reveal > 0
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
                        color: Qt.alpha(root.theme.hover, 0.36)
                        onClicked: root.store.invoke(root.entry.id, modelData.identifier)
                    }
                }
                ShellButton {
                    emberShell: root.emberShell
                    onHoveredChanged: root.followAction(this, hovered, false)
                    onActiveFocusChanged: root.followAction(this, activeFocus, true)
                    theme: root.theme; text: "Reply"; selected: true
                    color: Qt.alpha(root.theme.hover, 0.36)
                    visible: root.canReply && !root.composing
                    onClicked: { root.store.startReply(root.entry.id, root.inCenter ? "center" : "banner"); Qt.callLater(() => replyText.forceActiveFocus()) }
                }
            }
        }
        ColumnLayout {
            visible: root.composing
            Layout.fillWidth: true; spacing: 8
            TextField {
                font: root.theme.textFont
                id: replyText
                Layout.fillWidth: true; implicitHeight: 38
                color: root.theme.text; leftPadding: 10
                placeholderText: root.notification ? (root.notification.inlineReplyPlaceholder || "Reply…") : "Reply…"
                placeholderTextColor: root.theme.secondary
                text: root.store.drafts[root.entry.id] || ""
                selectByMouse: true
                cursorVisible: false
                EmberControl {
                    control: replyText; trackHover: false; caret: true
                    x: replyText.cursorRectangle.x; y: replyText.cursorRectangle.y
                    width: 3; height: replyText.cursorRectangle.height || 19
                    shapeRadius: 1.5; shapeOpacity: 1
                }
                background: Rectangle {
                    color: Qt.alpha(root.theme.background, 0.65); radius: 8
                    border.width: 1; border.color: Qt.alpha(root.theme.border, 0.3)
                }
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
