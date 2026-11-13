import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: root
    required property var shell
    required property var theme
    property var expandedGroups: ({})
    property var groupsByKey: ({})
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
    function toggleGroup(key) {
        const next = Object.assign({}, expandedGroups); next[key] = !next[key]; expandedGroups = next;
    }
    spacing: 0
    ColumnLayout {
        Layout.fillWidth: true; Layout.fillHeight: true
        Layout.rightMargin: 24; spacing: 20
        ListView {
            id: notificationList
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 18
            model: groupModel
            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 120 } }
            remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 100 } }
            displaced: Transition { NumberAnimation { properties: "x,y"; duration: 120; easing.type: Easing.OutCubic } }
            HoverHandler { onHoveredChanged: root.shell.notifications.centerHovered = hovered }
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: NotificationGroup {
                required property string groupKey
                width: notificationList.width; theme: root.theme; store: root.shell.notifications; group: root.groupsByKey[groupKey]
                expanded: !!root.expandedGroups[groupKey]
                onToggleExpanded: root.toggleGroup(groupKey)
            }
            Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; anchors.centerIn: parent; visible: notificationList.count === 0; text: "No notifications"; color: root.theme.secondary }
        }
        RowLayout {
            Layout.fillWidth: true
            ShellButton { theme: root.theme; icon: root.shell.notifications.dnd ? "bell-off" : "bell"; text: "Do not disturb"; selected: root.shell.notifications.dnd; onClicked: root.shell.notifications.dnd = !root.shell.notifications.dnd }
            Item { Layout.fillWidth: true }
            ShellButton { theme: root.theme; icon: "list-x"; hint: "Clear notifications"; enabled: root.shell.notifications.entries.length > 0; onClicked: root.shell.notifications.clear() }
        }
    }
    Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: root.theme.surface }
    ScrollView {
        Layout.preferredWidth: 350; Layout.fillHeight: true
        Layout.leftMargin: 24
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        CalendarPane { width: 350; shell: root.shell; theme: root.theme }
    }
}
