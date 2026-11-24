import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var theme
    required property var store
    required property var group
    property var emberShell: null
    property int cardRevision: 0
    property var cardData: ({})
    property bool expanded: false
    property real unfold: expanded && cardModel.count > 1 ? 1 : 0
    Behavior on unfold { NumberAnimation { duration: 260; easing.type: Easing.InOutCubic } }
    signal cardClicked()
    signal toggleExpanded()
    readonly property var hoveredCard: findCard(c => c.hovered)
    readonly property var focusedCard: findCard(c => c.containsFocus)
    readonly property var firstUnreadCard: findCard(c => !c.entry.read)
    property bool presented: true
    property bool geometryReady: false
    signal retired()
    readonly property int frontIndex: {
        const revision = cardRevision;
        for (let i = 0; i < cardModel.count; ++i) if (cardModel.get(i).wanted) return i;
        return -1;
    }
    readonly property int activeCount: {
        const revision = cardRevision;
        let count = 0;
        for (let i = 0; i < cardModel.count; ++i) if (cardModel.get(i).wanted) count++;
        return count;
    }
    readonly property var firstCard: { const revision = cardRevision; return cardViews.itemAt(Math.max(0, frontIndex)); }
    readonly property int stackCount: Math.min(2, Math.max(0, activeCount - 1))
    readonly property real firstBottom: firstCard ? firstCard.height : 0
    property real collapsedHeight: firstBottom + stack.height
    Behavior on collapsedHeight { enabled: root.geometryReady && root.frontIndex >= 0; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    implicitHeight: cardModel.count ? collapsedHeight * (1 - unfold) + content.implicitHeight * unfold : 0
    Connections {
        target: root.Window.window
        enabled: !root.geometryReady
        function onFrameSwapped() { root.geometryReady = true; }
    }
    function findCard(predicate) {
        const revision = cardRevision, count = cardViews.count;
        for (let i = 0; i < count; i++) {
            const card = cardViews.itemAt(i);
            if (card && card.visible && card.enabled && (i === frontIndex || unfold > 0.95) && predicate(card)) return card;
        }
        return null;
    }
    function syncCards() {
        if (!group || !store) return;
        const data = Object.assign({}, cardData);
        for (const entry of group.entries) data[entry.id] = entry;
        cardData = data;
        const wanted = presented ? group.entries.filter(entry => !store.removing[entry.id]).map(entry => entry.id) : [];
        for (let i = 0; i < cardModel.count; ++i) {
            const row = cardModel.get(i), keep = wanted.includes(row.entryId);
            const card = cardViews.itemAt(i);
            if (!keep && row.wanted && card) card.beginDismissal();
            if (keep && !row.wanted && card) card.cancelDismissal();
            cardModel.setProperty(i, "wanted", keep);
        }
        let position = 0;
        for (const id of wanted) {
            // Leave retiring rows in place until their pixels and space have
            // animated out; only reorder the surviving rows around those slots.
            while (position < cardModel.count && !cardModel.get(position).wanted) position++;
            let at = -1;
            for (let j = 0; j < cardModel.count; ++j) if (cardModel.get(j).entryId === id) { at = j; break; }
            if (at < 0) cardModel.insert(position, {entryId: id, wanted: true});
            else if (at !== position) cardModel.move(at, position, 1);
            position++;
        }
        cardRevision++;
        if (!cardModel.count && !presented) retired();
    }
    function retireCard(id) {
        for (let i = 0; i < cardModel.count; ++i) {
            if (cardModel.get(i).entryId !== id) continue;
            if (cardModel.get(i).wanted) return;
            cardModel.remove(i);
            break;
        }
        const data = Object.assign({}, cardData); delete data[id]; cardData = data;
        cardRevision++;
        if (!cardModel.count && !presented) retired();
    }
    onPresentedChanged: syncCards()
    onStoreChanged: syncCards()
    Connections { target: root.store; function onRemovingChanged() { root.syncCards(); } }
    onGroupChanged: syncCards()
    Component.onCompleted: syncCards()
    ListModel { id: cardModel }
    Item {
        x: 0; y: -28; width: root.width; height: root.height + 28
        clip: true
        Column {
            id: content
            y: 28
            width: root.width; spacing: 10
            Repeater {
                id: cardViews
                onItemAdded: root.cardRevision++
                onItemRemoved: root.cardRevision++
                model: cardModel
                NotificationCard {
                    id: centerCard
                    required property string entryId
                    required property int index
                    required property bool wanted
                    // Keep the previous top card beneath the incoming card
                    // until it lands, even when the stack is collapsed.
                    readonly property bool landingUnderlay: !retiring && index === root.frontIndex + 1 && !!root.firstCard && root.firstCard.arrival < 1
                    width: root.width; height: implicitHeight
                    enabled: wanted && (index === root.frontIndex || root.unfold > 0.95)
                    z: cardModel.count - index
                    groupReveal: index === root.frontIndex || landingUnderlay ? 1 : root.unfold
                    groupOffset: index === root.frontIndex || landingUnderlay ? -y * (1 - root.unfold) : 0
                    onRetired: root.retireCard(entryId)
                    theme: root.theme; store: root.store; entry: root.cardData[entryId]
                    inCenter: true; emberShell: root.emberShell
                    Component.onCompleted: {
                        if (root.geometryReady) { arrival = 0; memberEntrance.start(); }
                    }
                    NumberAnimation {
                        id: memberEntrance
                        target: centerCard; property: "arrival"; from: 0; to: 1
                        duration: 300; easing.type: Easing.OutCubic
                    }
                    groupControls: index === root.frontIndex && root.activeCount > 1
                    groupCount: root.activeCount
                    groupExpanded: root.expanded
                    onClicked: root.cardClicked()
                    onToggleGroup: root.toggleExpanded()
                    onDismissGroup: root.store.removeGroup(root.group.key)
                }
            }
            RowLayout {
                objectName: "notificationGroupCollapse"
                width: root.width; height: 32
                visible: cardModel.count > 1 && root.unfold > 0
                opacity: root.unfold; enabled: root.unfold > 0.95
                Item { Layout.fillWidth: true }
                ShellButton { theme: root.theme; icon: "chevron-up"; hint: "Collapse notifications"; onClicked: root.toggleExpanded() }
            }
        }
        NotificationStack {
            id: stack
            width: root.width
            y: 28 + Math.max(root.firstBottom, root.height - height)
            theme: root.theme; count: root.stackCount; inset: true
            opacity: 1 - root.unfold
            visible: count > 0 && opacity > 0
        }
    }
}
