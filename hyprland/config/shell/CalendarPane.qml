import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    property date month: new Date(shell.clock.date.getFullYear(), shell.clock.date.getMonth(), 1)
    readonly property Item emberTarget: {
        const date = selectedDate, days = monthDays, count = dayCells.count;
        for (let i = 0; i < count; i++) {
            const cell = dayCells.itemAt(i);
            if (cell && sameDate(cell.modelData, date)) return cell.emberSlot;
        }
        return null;
    }
    readonly property date selectedDate: shell.agenda.selectedDate
    readonly property var monthDays: {
        const first = new Date(month.getFullYear(), month.getMonth(), 1);
        const start = (first.getDay() + 6) % 7;
        return Array.from({length: 42}, (_, index) => new Date(first.getFullYear(), first.getMonth(), 1 - start + index));
    }
    spacing: 15
    function sameDate(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate() }
    function moveMonth(delta) { month = new Date(month.getFullYear(), month.getMonth() + delta, 1) }
    function reset() { month = new Date(shell.clock.date.getFullYear(), shell.clock.date.getMonth(), 1); shell.agenda.selectDate(shell.clock.date) }
    Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; text: Qt.formatDateTime(root.selectedDate, "d MMMM yyyy"); color: root.theme.text }
    ColumnLayout {
        Layout.fillWidth: true; spacing: 8
        RowLayout {
            Layout.fillWidth: true
            ShellButton { theme: root.theme; icon: "chevron-left"; iconSize: 28; implicitWidth: 42; implicitHeight: 42; hint: "Previous month"; onClicked: root.moveMonth(-1) }
            Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: Qt.formatDateTime(root.month, "MMMM yyyy"); color: root.theme.text }
            ShellButton { theme: root.theme; icon: "chevron-right"; iconSize: 28; implicitWidth: 42; implicitHeight: 42; hint: "Next month"; onClicked: root.moveMonth(1) }
        }
        GridLayout {
            id: calendarGrid
            readonly property real cellSize: (width - columnSpacing * 6) / 7
            Layout.fillWidth: true
            columns: 7; columnSpacing: 4; rowSpacing: 4
            uniformCellWidths: true; uniformCellHeights: true
            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]
                Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; required property string modelData; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData; color: root.theme.secondary; Layout.preferredHeight: calendarGrid.cellSize; verticalAlignment: Text.AlignVCenter }
            }
            Repeater {
                id: dayCells
                model: root.monthDays
                Item {
                    id: day
                    property alias emberSlot: dateSlot
                    required property var modelData
                    Layout.fillWidth: true; Layout.preferredHeight: calendarGrid.cellSize
                    Layout.minimumHeight: calendarGrid.cellSize; Layout.maximumHeight: calendarGrid.cellSize
                    readonly property bool today: root.sameDate(modelData, root.shell.clock.date)
                    readonly property bool selected: root.sameDate(modelData, root.selectedDate)
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(42, parent.width); height: width; radius: width / 2
                        color: day.selected && !dateSlot.occupied ? root.theme.accent : "transparent"
                    border.width: day.today && !day.selected ? 1 : 0; border.color: root.theme.accent
                    }
                    EmberSlot { id: dateSlot; shell: root.shell; anchors.centerIn: parent; width: Math.min(42, parent.width); height: width }
                    opacity: modelData.getMonth() === root.month.getMonth() ? 1 : 0.35
                    Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; anchors.centerIn: parent; text: day.modelData.getDate(); color: day.selected && (!dateSlot.occupied || dateSlot.landed) ? root.theme.background : root.theme.text }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.shell.agenda.selectDate(day.modelData) }
                }
            }
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.theme.border; visible: root.shell.agenda.configured || root.shell.agenda.clocks.length > 0 }
    ColumnLayout {
        visible: root.shell.agenda.configured
        Layout.fillWidth: true; spacing: 10
        Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; visible: root.shell.agenda.events.length === 0; text: root.shell.agenda.loading && !root.shell.agenda.cached ? "Loading…" : root.shell.agenda.unavailable ? "Calendar unavailable" : "No events"; color: root.theme.secondary }
        Repeater {
            model: root.shell.agenda.events
            RowLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 12
                Rectangle { implicitWidth: 3; Layout.fillHeight: true; radius: 2; color: root.theme.accent }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 3
                    Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; Layout.fillWidth: true; text: modelData.title; textFormat: Text.PlainText; color: root.theme.text; wrapMode: Text.Wrap }
                    Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; text: modelData.allDay ? "All day" : Qt.formatDateTime(new Date(modelData.start), "hh:mm") + " – " + Qt.formatDateTime(new Date(modelData.end), "hh:mm"); color: root.theme.secondary }
                }
            }
        }
        Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; visible: root.shell.agenda.unavailable && root.shell.agenda.events.length > 0; text: "Some calendars are unavailable"; color: root.theme.secondary }
    }
    ColumnLayout {
        visible: root.shell.agenda.clocks.length > 0
        Layout.fillWidth: true; spacing: 10
        Repeater {
            model: root.shell.agenda.clocks
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; Layout.fillWidth: true; text: modelData.name; textFormat: Text.PlainText; color: root.theme.secondary }
                Text { font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize; text: root.shell.agenda.clockTime(modelData.offset); color: root.theme.text }
            }
        }
    }

}
