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
    signal toggleExpanded()
    readonly property var hoveredCard: findCard(c => c.hovered)
    readonly property var focusedCard: findCard(c => c.containsFocus)
    readonly property var firstUnreadCard: findCard(c => !c.entry.read)
    readonly property var firstCard: { const revision = cardRevision; return cardViews.itemAt(0); }
    readonly property int stackCount: Math.min(2, Math.max(0, cardModel.count - 1))
    readonly property real firstBottom: firstCard ? firstCard.y + firstCard.height : 0
    readonly property real collapsedHeight: firstBottom + stackCount * 12
    implicitHeight: cardModel.count ? collapsedHeight * (1 - unfold) + content.implicitHeight * unfold : 0
    clip: true
    function findCard(predicate) {
        const revision = cardRevision, count = cardViews.count;
        for (let i = 0; i < count; i++) {
            const card = cardViews.itemAt(i);
            if (card && card.visible && card.enabled && (i === 0 || unfold > 0.95) && predicate(card)) return card;
        }
        return null;
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
        cardRevision++;
    }
    onGroupChanged: syncCards()
    Component.onCompleted: syncCards()
    ListModel { id: cardModel }
    Column {
        id: content
        width: root.width; spacing: 10
        RowLayout {
            width: root.width; height: 32; spacing: 9
            Image {
                Layout.preferredWidth: 21; Layout.preferredHeight: 21
                source: root.group.icon ? (/^(file:|image:|\/)/.test(root.group.icon) ? root.group.icon : Quickshell.iconPath(root.group.icon, true)) : Quickshell.iconPath("application-x-executable", true)
                sourceSize.width: 42; sourceSize.height: 42
                fillMode: Image.PreserveAspectFit
                visible: source.toString().length > 0 && status !== Image.Error
            }
            Text {
                Layout.fillWidth: true; text: root.group.app; textFormat: Text.PlainText
                color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize
                elide: Text.ElideRight
            }
            ShellButton { objectName: "notificationGroupToggle"; visible: root.group.entries.length > 1; theme: root.theme; icon: root.expanded ? "chevron-up" : "chevron-down"; implicitWidth: 30; implicitHeight: 30; hint: root.expanded ? "Collapse notifications" : "Expand notifications"; onClicked: root.toggleExpanded() }
            ShellButton { theme: root.theme; icon: "x"; implicitWidth: 30; implicitHeight: 30; hint: "Dismiss " + root.group.app + " notifications"; onClicked: root.store.removeGroup(root.group.key) }
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
                enabled: index === 0 || root.unfold > 0.95
                groupReveal: index === 0 ? 1 : root.unfold
                theme: root.theme; store: root.store; entry: root.cardData[entryId]
                inCenter: true; emberShell: root.emberShell
            }
        }
        RowLayout {
            width: root.width; height: 32
            opacity: root.unfold; enabled: root.unfold > 0.95
            Item { Layout.fillWidth: true }
            ShellButton { theme: root.theme; icon: "chevron-up"; hint: "Collapse notifications"; onClicked: root.toggleExpanded() }
        }
    }
    // The real cards keep their natural Column positions. The stack only paints
    // the bottom edge, so it cannot bleed through a translucent front card.
    Item {
        width: root.width; height: root.stackCount * 12
        y: Math.max(root.firstBottom, root.height - height)
        clip: true; z: 2
        opacity: 1 - root.unfold; visible: root.stackCount > 0 && opacity > 0
        Repeater {
            model: root.stackCount
            Rectangle {
                required property int index
                readonly property int depth: index + 1
                x: depth * 9; y: depth * 12 - height
                width: root.width - depth * 18; height: 80
                radius: 12; z: 10 - depth
                color: depth === 1 ? "#756b64" : "#5d5651"
            }
        }
    }
}
