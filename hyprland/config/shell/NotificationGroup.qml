import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var theme
    required property var store
    required property var group
    property bool expanded: false
    property var cardData: ({})
    signal toggleExpanded()
    function syncCards() {
        const data = Object.assign({}, cardData);
        for (const entry of group.entries) data[entry.id] = entry;
        cardData = data;
        const wanted = (expanded ? group.entries : group.entries.slice(0, 1)).map(e => e.id);
        for (let i = cardModel.count - 1; i >= 0; --i) if (!wanted.includes(cardModel.get(i).entryId)) cardModel.remove(i);
        for (let i = 0; i < wanted.length; ++i) {
            let at = -1;
            for (let j = i; j < cardModel.count; ++j) if (cardModel.get(j).entryId === wanted[i]) { at = j; break; }
            if (at < 0) cardModel.insert(i, {entryId: wanted[i]});
            else if (at !== i) cardModel.move(at, i, 1);
        }
    }
    onGroupChanged: syncCards()
    onExpandedChanged: syncCards()
    Component.onCompleted: syncCards()
    ListModel { id: cardModel }
    implicitHeight: cards.implicitHeight + (!expanded && group.entries.length > 1 ? 10 : 0)
    clip: false
    Rectangle {
        visible: !root.expanded && root.group.entries.length > 2
        x: 14; width: parent.width - 28; height: 24; y: parent.height - height
        radius: 10; color: root.theme.surface; opacity: 0.45
    }
    Rectangle {
        visible: !root.expanded && root.group.entries.length > 1
        x: 7; width: parent.width - 14; height: 24; y: parent.height - height - 5
        radius: 10; color: root.theme.surface; opacity: 0.75
    }
    ColumnLayout {
        id: cards
        width: parent.width
        spacing: 8
        Repeater {
            model: cardModel
            NotificationCard {
                required property string entryId
                required property int index
                Layout.fillWidth: true
                theme: root.theme; store: root.store; entry: root.cardData[entryId]
                inCenter: true
                groupControls: index === 0 && root.group.entries.length > 1
                groupExpanded: root.expanded; groupKey: root.group.key
                onToggleGroup: root.toggleExpanded()
            }
        }
        RowLayout {
            visible: root.expanded && root.group.entries.length > 1
            Layout.fillWidth: true; spacing: 4
            Item { Layout.fillWidth: true }
            ShellButton { theme: root.theme; icon: "chevron-up"; hint: "Collapse notifications"; onClicked: root.toggleExpanded() }
            ShellButton { theme: root.theme; icon: "x"; hint: "Dismiss group"; onClicked: root.store.removeGroup(root.group.key) }
        }
    }
}
