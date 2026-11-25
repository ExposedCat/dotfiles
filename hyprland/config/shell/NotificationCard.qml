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
    EmberSlot {
        id: unreadSlot
        shell: root.emberShell
        x: 4; y: surface.radius; width: 3; height: Math.max(width, parent.height - 2 * y)
    }
    property bool groupControls: false
    property bool groupExpanded: false
    property int groupCount: 1
    signal clicked()
    signal toggleGroup()
    signal dismissGroup()
    property bool geometryReady: false
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
        id: surface
        anchors.fill: parent; z: -1
        theme: root.theme; critical: !!root.entry.critical
    }
    Connections {
        enabled: !root.geometryReady
        target: root.Window.window
        function onFrameSwapped() { root.geometryReady = true }
    }
    MouseArea {
        anchors.fill: parent
        enabled: !root.removing
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.canActivate) root.store.invoke(root.entry.id, "default");
            else if (!root.inCenter) root.store.dismissBanner(root.entry.id);
            root.clicked();
        }
    }
    HoverHandler { id: cardHover }
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
                Layout.preferredWidth: 40
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: content.anchors.leftMargin - content.anchors.topMargin
                sourceSize.width: 112; sourceSize.height: 112
                fillMode: iconSource.startsWith("image://icon/") ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                RowLayout {
                    Layout.fillWidth: true; spacing: 7
                    Text { font: root.theme.textFont; Layout.fillWidth: true; text: root.entry.summary; textFormat: Text.PlainText; color: root.theme.text; wrapMode: Text.NoWrap; maximumLineCount: 1; elide: Text.ElideRight }
                    ShellButton { objectName: "notificationGroupToggle"; visible: root.groupControls; theme: root.theme; icon: root.groupExpanded ? "chevron-up" : "chevron-down"; hint: root.groupExpanded ? "Collapse notifications" : "Expand notifications"; implicitWidth: 30; implicitHeight: 30; Layout.alignment: Qt.AlignTop; onClicked: root.toggleGroup() }
                    NotificationDismiss {
                        objectName: "notificationDismiss"
                        theme: root.theme
                        hint: "Dismiss notification"
                        grouped: root.groupCount > 1
                        enabled: !root.removing
                        Layout.alignment: Qt.AlignTop
                        onClicked: root.store.remove(root.entry.id)
                        onGroupDismissed: root.dismissGroup()
                    }
                }
                Text { id: body; objectName: "notificationBody"; font: root.theme.textFont; visible: text.length > 0; Layout.fillWidth: true; text: root.entry.body; textFormat: Text.PlainText; color: root.theme.secondary; wrapMode: Text.Wrap; maximumLineCount: 5; elide: Text.ElideRight }
            }
        }
        Flow {
            id: actions
            objectName: "notificationActions"
            Layout.fillWidth: true
            visible: root.hasActions || (root.canReply && !root.composing)
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
