import QtQuick
import Quickshell

PopupWindow {
    id: popup
    required property var theme
    property var trayItem: null
    property var levels: []
    readonly property var currentMenu: levels.length ? levels[levels.length - 1] : rootMenu
    readonly property var entries: currentMenu ? currentMenu.children.values : []
    readonly property string heading: levels.length ? levels[levels.length - 1].heading : ""
    implicitWidth: 300
    implicitHeight: Math.min(620, Math.max(44, list.contentHeight) + (levels.length ? 40 : 0) + 16, screen ? screen.height - 70 : 620)
    color: "transparent"
    grabFocus: true

    function label(text) { return text.replace(/&&/g, "\u0001").replace(/&/g, "").replace(/\u0001/g, "&") }
    function clearLevels() {
        const old = levels;
        levels = [];
        for (let i = old.length - 1; i >= 0; --i) old[i].destroy();
    }
    function open(item, window, x, y, width) {
        visible = false;
        clearLevels();
        trayItem = item;
        anchor.window = window;
        anchor.rect = Qt.rect(x, y + theme.panelGap, width, 1);
        visible = !!item && item.hasMenu;
        Qt.callLater(() => {
            if (!visible) return;
            content.forceActiveFocus();
            selectFirst();
        });
    }
    function selectFirst() {
        list.currentIndex = -1;
        move(1);
    }
    function move(step) {
        for (let n = 1; n <= entries.length; ++n) {
            const at = (list.currentIndex + step * n + entries.length) % entries.length;
            if (entries[at].enabled && !entries[at].isSeparator) {
                list.currentIndex = at;
                list.positionViewAtIndex(at, ListView.Contain);
                return;
            }
        }
    }
    function activate(entry) {
        if (!entry || !entry.enabled || entry.isSeparator) return;
        if (entry.hasChildren) {
            // Keep every parent opener alive while its submenu is in use.
            const next = submenu.createObject(popup, {menu: entry, heading: label(entry.text)});
            levels = levels.concat([next]);
            Qt.callLater(selectFirst);
        } else {
            entry.triggered();
            visible = false;
        }
    }
    function back() {
        if (!levels.length) { visible = false; return }
        const old = levels[levels.length - 1];
        levels = levels.slice(0, -1);
        old.destroy();
        selectFirst();
    }
    onVisibleChanged: if (!visible) { clearLevels(); trayItem = null }
    onTrayItemChanged: if (!trayItem) visible = false
    onEntriesChanged: Qt.callLater(selectFirst)
    Connections { target: popup.trayItem; function onHasMenuChanged() { if (!popup.trayItem.hasMenu) popup.visible = false } }
    QsMenuOpener { id: rootMenu; menu: popup.visible && popup.trayItem ? popup.trayItem.menu : null }
    Component { id: submenu; QsMenuOpener { property string heading: "" } }

    Rectangle {
        anchors.fill: parent
        color: popup.theme.background
        border.width: 1; border.color: popup.theme.border
        radius: 12
    }
    FocusScope {
        id: content
        anchors { fill: parent; margins: 8 }
        focus: true
        Keys.onEscapePressed: popup.visible = false
        Keys.onUpPressed: popup.move(-1)
        Keys.onDownPressed: popup.move(1)
        Keys.onLeftPressed: popup.back()
        Keys.onRightPressed: { const entry = popup.entries[list.currentIndex]; if (entry && entry.hasChildren) popup.activate(entry) }
        Keys.onReturnPressed: popup.activate(popup.entries[list.currentIndex])
        Keys.onEnterPressed: popup.activate(popup.entries[list.currentIndex])
        Keys.onSpacePressed: popup.activate(popup.entries[list.currentIndex])
        Column {
            id: body
            width: parent.width
            spacing: 4
            ShellButton {
                width: parent.width
                visible: popup.levels.length > 0
                theme: popup.theme; icon: "chevron-left"; text: popup.heading
                elideText: true
                onClicked: popup.back()
            }
            ListView {
                id: list
                width: parent.width
                height: Math.min(content.height - (popup.levels.length ? 40 : 0), contentHeight)
                implicitHeight: contentHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: popup.entries
                currentIndex: -1
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool separator: modelData.isSeparator
                    readonly property bool available: !separator && modelData.enabled
                    readonly property bool selected: ListView.isCurrentItem
                    width: list.width
                    height: separator ? 13 : 40
                    radius: 7
                    color: selected && available ? popup.theme.hover : "transparent"
                    Accessible.role: Accessible.MenuItem
                    Accessible.name: separator ? "" : popup.label(modelData.text)
                    Accessible.onPressAction: popup.activate(modelData)
                    Rectangle { visible: row.separator; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: popup.theme.border }
                    Item {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        visible: !row.separator
                        opacity: row.available ? 1 : 0.4
                        Image {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: 18; height: 18; sourceSize.width: 18; sourceSize.height: 18
                            source: row.modelData.icon
                            visible: row.modelData.buttonType === QsMenuButtonType.None && source.toString().length > 0
                        }
                        Text {
                            font.family: popup.theme.fontFamily; font.weight: popup.theme.fontWeight; font.pixelSize: popup.theme.bodySize
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: 18; horizontalAlignment: Text.AlignHCenter
                            visible: row.modelData.buttonType !== QsMenuButtonType.None
                            text: row.modelData.checkState === Qt.Checked ? (row.modelData.buttonType === QsMenuButtonType.RadioButton ? "●" : "✓") : row.modelData.checkState === Qt.PartiallyChecked ? "−" : ""
                            color: popup.theme.accent;
                        }
                        Text {
                            font.family: popup.theme.fontFamily; font.weight: popup.theme.fontWeight; font.pixelSize: popup.theme.bodySize
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 28; rightMargin: 22 }
                            text: popup.label(row.modelData.text)
                            textFormat: Text.PlainText; elide: Text.ElideRight
                            color: popup.theme.text;
                        }
                        ShellIcon { anchors { right: parent.right; verticalCenter: parent.verticalCenter } width: 17; height: 17; name: "chevron-right"; visible: row.modelData.hasChildren }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: row.available
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: list.currentIndex = row.index
                        onClicked: popup.activate(row.modelData)
                    }
                }
            }
            Text { font.family: popup.theme.fontFamily; font.weight: popup.theme.fontWeight; font.pixelSize: popup.theme.bodySize; visible: !popup.entries.length; text: "Loading…"; color: popup.theme.secondary; padding: 12 }
        }
    }
}
