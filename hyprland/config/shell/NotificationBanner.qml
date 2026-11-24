import QtQuick
import Quickshell

// Retain a banner's geometry and pixels until it is completely off-screen.
Item {
    id: root
    required property var theme
    required property var store
    required property var group
    property bool expanded: false
    property real unfold: expanded && cardModel.count > 1 ? 1 : 0
    Behavior on unfold { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }
    property var cardData: ({})
    property int cardRevision: 0
    readonly property var firstCard: { const revision = cardRevision; return cards.itemAt(0); }
    readonly property int stackCount: Math.min(2, Math.max(0, cardModel.count - 1))
    readonly property real collapsedHeight: (firstCard ? firstCard.height : 0) + stack.height
    readonly property real contentHeight: collapsedHeight * (1 - unfold) + content.implicitHeight * unfold
    property bool presented: true
    property real travel: width + theme.panelGap
    property real offset: 0
    property real arrival: 0
    readonly property real dropOffset: -28 * (1 - arrival)
    readonly property real tilt: -3 * (1 - arrival)
    property real heldHeight: 0
    property bool ready: false
    property bool retiredSent: false
    property point lastHoverPosition: Qt.point(-1, -1)
    readonly property bool hoverHeld: groupHover.enabled && (groupHover.hovered || hoverExit.running)
    readonly property alias inputRegion: input
    signal retired()
    signal inputGeometryChanged()
    x: offset
    opacity: Math.min(1, arrival)
    transform: [
        Translate { y: root.dropOffset },
        Rotation { origin.x: root.width * 0.7; origin.y: 0; angle: root.tilt }
    ]
    implicitHeight: !presented && heldHeight > 0 ? heldHeight : contentHeight
    enabled: presented && ready && arrival === 1

    function animate() {
        if (!ready) return;
        motion.stop();
        motion.to = presented ? 0 : travel;
        motion.restart();
    }
    onPresentedChanged: {
        heldHeight = presented ? 0 : Math.max(1, height);
        if (presented) retiredSent = false;
        animate();
    }
    onTravelChanged: { if (ready && !presented) animate(); }
    NumberAnimation {
        id: entrance
        target: root; property: "arrival"; from: 0; to: 1
        duration: 300; easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: motion
        target: root; property: "offset"
        duration: 220; easing.type: Easing.OutCubic
        onFinished: {
            if (!root.presented && !root.retiredSent) {
                root.retiredSent = true;
                root.retired();
            }
        }
    }
    Connections {
        target: root.Window.window
        enabled: !root.ready
        function onFrameSwapped() { root.ready = true; entrance.start(); root.animate(); }
    }
    Region {
        id: input
        item: root.enabled ? root : null
        onChanged: { if (root.enabled) root.inputGeometryChanged(); }
    }
    function syncCards() {
        if (!group) return;
        const data = Object.assign({}, cardData);
        for (const member of group.entries) data[member.id] = member;
        cardData = data;
        const ids = group.entries.map(member => member.id);
        for (let i = cardModel.count - 1; i >= 0; --i)
            if (!ids.includes(cardModel.get(i).entryId)) cardModel.remove(i);
        for (let i = 0; i < ids.length; ++i) {
            let at = -1;
            for (let j = i; j < cardModel.count; ++j)
                if (cardModel.get(j).entryId === ids[i]) { at = j; break; }
            if (at < 0) cardModel.insert(i, {entryId: ids[i]});
            else if (at !== i) cardModel.move(at, i, 1);
        }
        cardRevision++;
    }
    onGroupChanged: syncCards()
    Component.onCompleted: syncCards()
    ListModel { id: cardModel }
    HoverHandler {
        id: groupHover
        enabled: root.enabled && !root.store.presentationPaused
        function rememberPosition() {
            if (root.contains(point.position)) root.lastHoverPosition = point.scenePosition;
        }
        onPointChanged: { if (hovered) rememberPosition(); }
        onHoveredChanged: {
            if (hovered) {
                rememberPosition();
                hoverExit.stop();
            } else if (enabled) {
                // Reflow can move or shrink a card under a stationary pointer.
                hoverExit.consume = root.contains(root.mapFromItem(null, root.lastHoverPosition));
                hoverExit.restart();
            }
        }
        onEnabledChanged: { if (!enabled) hoverExit.stop(); }
    }
    Timer {
        id: hoverExit; interval: 80
        property bool consume: false
        onTriggered: {
            if (consume && groupHover.enabled && !groupHover.hovered)
                root.store.dismissPopupGroup(root.group.key);
        }
    }
    Item {
        // Leave headroom for a new member to fall onto an existing stack,
        // while clipping hidden cards below the group's animated height.
        x: 0; y: -32; width: root.width; height: root.height + 32
        clip: true
        Column {
            id: content
            y: 32
            width: root.width; spacing: 10
            Repeater {
                id: cards
                model: cardModel
                onItemAdded: root.cardRevision++
                onItemRemoved: root.cardRevision++
                NotificationCard {
                    id: bannerCard
                    required property string entryId
                    required property int index
                    objectName: "notification-banner-card"
                    width: root.width; height: implicitHeight
                    property real landing: 1
                    opacity: (index === 0 ? 1 : root.unfold) * landing
                    enabled: (index === 0 || root.unfold > 0.95) && landing === 1
                    transform: [
                        Translate { y: -24 * (1 - landing) },
                        Rotation { origin.x: bannerCard.width * 0.7; origin.y: 0; angle: -3 * (1 - landing) }
                    ]
                    Component.onCompleted: {
                        if (root.ready) { landing = 0; memberEntrance.start(); }
                    }
                    NumberAnimation {
                        id: memberEntrance
                        target: bannerCard; property: "landing"; from: 0; to: 1
                        duration: 300; easing.type: Easing.OutCubic
                    }
                    theme: root.theme; store: root.store; entry: root.cardData[entryId]
                    groupControls: index === 0 && cardModel.count > 1
                    groupCount: cardModel.count
                    groupExpanded: root.expanded
                    onToggleGroup: root.expanded = !root.expanded
                    onDismissGroup: root.store.removePopupGroup(root.group.key)
                }
            }
        }
        NotificationStack {
            id: stack
            width: root.width
            y: 32 + (root.firstCard ? root.firstCard.height : 0)
            theme: root.theme; count: root.stackCount
            opacity: 1 - root.unfold
            visible: count > 0 && opacity > 0
        }
    }
}
