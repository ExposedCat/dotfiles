import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var theme
    required property var store
    required property var group
    property bool expanded: false
    property var emberShell: null
    property int cardRevision: 0
    property var cardData: ({})
    property real unfold: expanded ? 1 : 0
    Behavior on unfold { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }
    readonly property var hoveredCard: findCard(c => c.hovered || c.containsFocus)
    readonly property var firstUnreadCard: findCard(c => !c.entry.read)
    readonly property var firstCard: { const revision = cardRevision; return cardViews.itemAt(0); }
    readonly property real firstHeight: firstCard ? firstCard.implicitHeight : 0
    readonly property int stackCount: Math.min(2, Math.max(0, cardModel.count - 1))
    readonly property real openHeight: rowY(cardModel.count) + (cardModel.count > 1 ? 36 : 0)
    implicitHeight: (firstHeight + stackCount * 12) * (1 - unfold) + openHeight * unfold
    clip: true
    signal toggleExpanded()
    function findCard(predicate) {
        const revision = cardRevision, count = cardViews.count;
        for (let i = 0; i < count; i++) {
            const card = cardViews.itemAt(i);
            if (card && card.visible && card.enabled && (i === 0 || unfold > 0.9) && predicate(card)) return card;
        }
        return null;
    }
    function rowY(index) {
        const revision = cardRevision;
        let y = 0;
        for (let i = 0; i < index; i++) { const card = cardViews.itemAt(i); y += (card ? card.implicitHeight : 0) + 8; }
        return y;
    }
    function syncCards() {
        const data = Object.assign({}, cardData);
        for (const entry of group.entries) data[entry.id] = entry;
        cardData = data;
        const wanted = group.entries.map(e => e.id);
        for (let i = cardModel.count - 1; i >= 0; --i) if (!wanted.includes(cardModel.get(i).entryId)) cardModel.remove(i);
        for (let i = 0; i < wanted.length; ++i) {
            let at = -1;
            for (let j = i; j < cardModel.count; ++j) if (cardModel.get(j).entryId === wanted[i]) { at = j; break; }
            if (at < 0) cardModel.insert(i, {entryId: wanted[i]});
            else if (at !== i) cardModel.move(at, i, 1);
        }
    }
    onGroupChanged: syncCards()
    Component.onCompleted: syncCards()
    ListModel { id: cardModel }
    Repeater {
        model: root.stackCount
        Rectangle {
            required property int index
            readonly property int depth: index + 1
            x: depth * 9; width: root.width - depth * 18
            height: Math.min(80, root.firstHeight)
            y: (root.firstHeight - height + depth * 12) * (1 - root.unfold) + root.rowY(depth) * root.unfold
            radius: 12
            color: depth === 1 ? "#756b64" : "#5d5651"
            opacity: 1 - root.unfold
            visible: opacity > 0
            z: 10 - depth
        }
    }
    Repeater {
        id: cardViews
        onItemAdded: root.cardRevision++
        onItemRemoved: root.cardRevision++
        model: cardModel
        NotificationCard {
            required property string entryId
            required property int index
            width: root.width; height: implicitHeight
            y: index === 0 ? 0 : (root.firstHeight - Math.min(80, implicitHeight) + Math.min(index, 2) * 12) * (1 - root.unfold) + root.rowY(index) * root.unfold
            z: 100 - index
            visible: index === 0 || root.unfold > 0.001
            enabled: index === 0 || root.unfold > 0.9
            groupReveal: index === 0 ? 1 : root.unfold
            theme: root.theme; store: root.store; entry: root.cardData[entryId]
            hoverExpansionAllowed: root.unfold === 0 || root.unfold === 1
            inCenter: true; emberShell: root.emberShell
            groupControls: index === 0 && root.group.entries.length > 1
            groupExpanded: root.expanded; groupKey: root.group.key
            onToggleGroup: root.toggleExpanded()
        }
    }
    RowLayout {
        width: root.width; y: root.rowY(cardModel.count)
        opacity: root.unfold; visible: root.unfold > 0.001 && cardModel.count > 1; enabled: root.unfold > 0.9
        spacing: 4
        Item { Layout.fillWidth: true }
        ShellButton { theme: root.theme; icon: "chevron-up"; hint: "Collapse notifications"; onClicked: root.toggleExpanded() }
        ShellButton { theme: root.theme; icon: "x"; hint: "Dismiss group"; onClicked: root.store.removeGroup(root.group.key) }
    }
}
