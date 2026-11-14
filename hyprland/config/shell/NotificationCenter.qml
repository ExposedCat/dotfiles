import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: root
    required property var shell
    required property var theme
    property bool notificationMode: false
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
    onHoveredNotificationTargetChanged: { if (hoveredNotificationTarget) { lastNotificationTarget = hoveredNotificationTarget; notificationMode = true; } }
    onFocusedNotificationTargetChanged: { if (focusedNotificationTarget) { lastNotificationTarget = focusedNotificationTarget; notificationMode = true; } }
    readonly property Item emberTarget: {
        if (!notificationMode) return calendar.emberTarget;
        if (lastNotificationTarget) return lastNotificationTarget;
        const count = notificationList.count;
        for (let i = 0; i < count; i++) {
            const group = notificationList.itemAtIndex(i);
            const card = group?.firstUnreadCard || group?.firstCard;
            if (card) return card.emberTarget;
        }
        return calendar.emberTarget;
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
        for (let i = groupModel.count - 1; i >= 0; --i) if (!keys.includes(groupModel.get(i).groupKey)) groupModel.remove(i);
        for (let i = 0; i < keys.length; ++i) {
            let at = -1;
            for (let j = i; j < groupModel.count; ++j) if (groupModel.get(j).groupKey === keys[i]) { at = j; break }
            if (at < 0) groupModel.insert(i, {groupKey: keys[i]});
            else if (at !== i) groupModel.move(at, i, 1);
        }
    }
    ListModel { id: groupModel }
    Connections { target: root.shell.notifications; function onGroupsChanged() { root.syncGroups() } }
    Component.onCompleted: syncGroups()
    spacing: 24
    ColumnLayout {
        Layout.fillWidth: true; Layout.fillHeight: true
        spacing: 14
        ListView {
            id: notificationList
            objectName: "notificationList"
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 14
            model: groupModel
            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 } }
            remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 100 } }
            HoverHandler { onHoveredChanged: { root.shell.notifications.centerHovered = hovered; if (hovered) root.notificationMode = true; } }
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            PillWheel { flickable: notificationList }
            delegate: NotificationGroup {
                required property string groupKey
                width: notificationList.width; emberShell: root.shell; theme: root.theme; store: root.shell.notifications; group: root.groupsByKey[groupKey]
                expanded: !!root.expandedGroups[groupKey]
                onToggleExpanded: root.toggleGroup(groupKey)
            }
            Column {
                anchors.centerIn: parent; visible: notificationList.count === 0; spacing: 12
                ShellIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "bell-off"; width: 21; height: 21; opacity: 0.6 }
                Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; text: "No notifications"; color: root.theme.secondary }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            ShellButton { theme: root.theme; icon: root.shell.notifications.dnd ? "bell-off" : "bell"; text: "Do not disturb"; selected: root.shell.notifications.dnd; onClicked: root.shell.notifications.dnd = !root.shell.notifications.dnd }
            Item { Layout.fillWidth: true }
            ShellButton { theme: root.theme; icon: "list-x"; hint: "Clear notifications"; enabled: root.shell.notifications.entries.length > 0; onClicked: root.shell.notifications.clear() }
        }
    }
    ScrollView {
        id: calendarScroll
        Layout.preferredWidth: 350; Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        PillWheel { flickable: calendarScroll.contentItem }
        HoverHandler { onHoveredChanged: { if (hovered) root.notificationMode = false; } }
        CalendarPane { id: calendar; width: 350; shell: root.shell; theme: root.theme }
    }
}
