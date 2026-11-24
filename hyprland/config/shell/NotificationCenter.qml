import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    property real scrollBottomPadding: 0
    property Item lastNotificationTarget: null
    readonly property Item hoveredNotificationTarget: {
        const count = notificationList.count;
        for (let i = 0; i < count; i++) {
            const group = notificationList.itemAtIndex(i);
            if (group?.hoveredCard) return group.hoveredCard.emberTarget;
        }
        return null;
    }
    readonly property Item focusedNotificationTarget: {
        const count = notificationList.count;
        for (let i = 0; i < count; i++) {
            const group = notificationList.itemAtIndex(i);
            if (group?.focusedCard) return group.focusedCard.emberTarget;
        }
        return null;
    }
    onHoveredNotificationTargetChanged: { if (hoveredNotificationTarget) lastNotificationTarget = hoveredNotificationTarget; }
    onFocusedNotificationTargetChanged: { if (focusedNotificationTarget) lastNotificationTarget = focusedNotificationTarget; }
    readonly property Item emberTarget: {
        if (lastNotificationTarget) return lastNotificationTarget;
        const count = notificationList.count;
        for (let i = 0; i < count; i++) {
            const group = notificationList.itemAtIndex(i);
            const card = group?.firstUnreadCard || group?.firstCard;
            if (card) return card.emberTarget;
        }
        return null;
    }
    property var groupsByKey: ({})
    property var expandedGroups: ({})
    function toggleGroup(key) {
        const next = Object.assign({}, expandedGroups);
        next[key] = !next[key]; expandedGroups = next;
        if (!next[key]) {
            for (let i = 0; i < notificationList.count; i++) {
                const group = notificationList.itemAtIndex(i);
                if (group?.group.key === key && group.firstCard) { lastNotificationTarget = group.firstCard.emberTarget; break; }
            }
        }
    }
    function syncGroups() {
        const groups = shell.notifications.groups;
        const data = Object.assign({}, groupsByKey);
        for (const group of groups) data[group.key] = group;
        groupsByKey = data;
        const keys = groups.map(g => g.key);
        for (let i = 0; i < groupModel.count; ++i) groupModel.setProperty(i, "wanted", keys.includes(groupModel.get(i).groupKey));
        let position = 0;
        for (const key of keys) {
            while (position < groupModel.count && !groupModel.get(position).wanted) position++;
            let at = -1;
            for (let j = 0; j < groupModel.count; ++j) if (groupModel.get(j).groupKey === key) { at = j; break; }
            if (at < 0) groupModel.insert(position, {groupKey: key, wanted: true});
            else if (at !== position) groupModel.move(at, position, 1);
            position++;
        }
    }

    function retireGroup(key) {
        for (let i = 0; i < groupModel.count; ++i) {
            if (groupModel.get(i).groupKey !== key) continue;
            if (groupModel.get(i).wanted) return;
            groupModel.remove(i);
            break;
        }
        const data = Object.assign({}, groupsByKey); delete data[key]; groupsByKey = data;
    }
    ListModel { id: groupModel }
    Connections { target: root.shell.notifications; function onGroupsChanged() { root.syncGroups() } }
    Component.onCompleted: syncGroups()
    spacing: 6
    RowLayout {
        Layout.fillWidth: true
        PillToggle {
            theme: root.theme
            text: "Do not disturb"
            selected: root.shell.notifications.dnd
            icon: selected ? "bell-off" : "bell"
            onClicked: root.shell.notifications.dnd = !root.shell.notifications.dnd
        }
        Item { Layout.fillWidth: true }
        ShellButton { theme: root.theme; icon: "list-x"; hint: "Clear notifications"; enabled: root.shell.notifications.entries.length > 0; onClicked: root.shell.notifications.clear() }
    }
    ListView {
        id: notificationList
        objectName: "notificationList"
        Layout.fillWidth: true; Layout.fillHeight: true
        bottomMargin: root.scrollBottomPadding
        clip: true; spacing: 14
        model: groupModel
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        PillWheel { flickable: notificationList }
        delegate: NotificationGroup {
            required property string groupKey
            required property bool wanted
            presented: wanted
            onRetired: root.retireGroup(groupKey)
            width: notificationList.width; emberShell: root.shell; theme: root.theme; store: root.shell.notifications; group: root.groupsByKey[groupKey]
            // A ListView add transition retains positions measured before
            // wrapped card content settles. Fade without a view transition
            // so changing group heights continue to reflow their neighbors.
            NumberAnimation on opacity { from: 0; to: 1; duration: 120 }
            expanded: !!root.expandedGroups[groupKey]
            onCardClicked: { if (root.shell.panel === "notifications") root.shell.panel = ""; }
            onToggleExpanded: root.toggleGroup(groupKey)
        }
        Column {
            anchors.centerIn: parent; visible: notificationList.count === 0; spacing: 12
            ShellIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "bell-off"; width: 21; height: 21; opacity: 0.6 }
            Text { font: root.theme.textFont; text: "No notifications"; color: root.theme.secondary }
        }
    }
}
