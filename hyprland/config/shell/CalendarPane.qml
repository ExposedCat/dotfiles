import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts

Flickable {
    id: root
    required property var shell
    required property var theme
    readonly property var agenda: shell.agenda
    readonly property string selectedKey: agenda.dayKey(agenda.selectedDate)
    readonly property string todayKey: agenda.dayKey(shell.clock.date)
    readonly property bool showClockFlags: agenda.clocks.some(clock => countryFlag(clock.country).length > 0)
    readonly property bool showSidebar: agenda.configured || agenda.clocks.length > 0
    readonly property int preferredMonthWidth: 576
    readonly property int minimumMonthWidth: 436
    readonly property int cardGap: 14
    readonly property int cardPadding: 10
    readonly property int sidebarMinimumWidth: 180
    readonly property bool showCalendarWarning: agenda.unavailable && (agenda.eventsOn(selectedKey).length > 0 || agenda.eventsOn(agenda.dayKey(agenda.nextDate)).length > 0)
    readonly property int daySpacing: 2
    readonly property int monthHeadingHeight: 36
    readonly property int weekdayHeight: 26
    readonly property int monthHeadingSpacing: 6
    property date transitionStart: agenda.rangeStart
    property int monthDirection: 0
    property real monthProgress: 0
    property var pendingMoves: []
    property Item hoveredEvent: null
    readonly property var hoveredSpan: {
        if (!hoveredEvent) return null;
        const event = hoveredEvent.modelData;
        const start = new Date(event.start).getTime();
        const end = new Date(event.end).getTime();
        return {start: start, end: Math.max(end, start + 1), uid: seriesUid(event), calendarId: event.calendarId};
    }
    readonly property Item emberTarget: {
        if (hoveredEvent) return hoveredEvent.emberSlot;
        if (monthDirection) return null;
        for (let i = 0; i < Math.min(4, months.created); i++) {
            const slot = months.itemAt(i)?.selectedSlot;
            if (slot) return slot;
        }
        return null;
    }

    implicitHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: Math.max(width, minimumMonthWidth + (showSidebar ? cardGap + sidebarMinimumWidth : 0))
    contentHeight: content.height
    ScrollBar.vertical: ScrollBar {}
    ScrollBar.horizontal: ScrollBar {}
    PillWheel { flickable: root }
    onSelectedKeyChanged: {
        hoveredEvent = null;
        events.contentY = 0;
    }
    onEnabledChanged: {
        if (!enabled) {
            hoveredEvent = null;
            pendingMoves = [];
        }
    }

    function moveMonth(direction) {
        if (monthDirection) {
            pendingMoves.push(direction);
            return;
        }
        hoveredEvent = null;
        transitionStart = agenda.rangeStart;
        monthDirection = direction;
        agenda.rangeStart = agenda.monthOffset(transitionStart, direction);
        monthTransition.start();
    }

    NumberAnimation {
        id: monthTransition
        target: root; property: "monthProgress"
        from: 0; to: 1; duration: 220; easing.type: Easing.InOutCubic
        onFinished: {
            root.monthProgress = 0;
            root.monthDirection = 0;
            if (root.pendingMoves.length) root.moveMonth(root.pendingMoves.shift());
        }
    }

    function dayHeading(date) { return Qt.formatDateTime(date, "d MMMM yyyy"); }
    function emptyDayMessage(key) {
        if (agenda.loading && !agenda.cache[key]) return "Loading…";
        return agenda.unavailable ? "Calendar unavailable" : "No events";
    }
    function eventTime(event) {
        if (event.allDay) return "All day";
        return Qt.formatDateTime(new Date(event.start), "hh:mm") + " – " + Qt.formatDateTime(new Date(event.end), "hh:mm");
    }

    function seriesUid(event) {
        if (!event.calendarId || typeof event.id !== "string") return "";
        // The agenda helper appends the occurrence's Unix start time to its iCalendar UID.
        const suffix = ":" + (new Date(event.start).getTime() / 1000);
        return event.id.endsWith(suffix) ? event.id.slice(0, -suffix.length) : "";
    }

    function countryFlag(country) {
        const code = (country || "").toUpperCase();
        if (!/^[A-Z]{2}$/.test(code)) return "";
        return String.fromCodePoint(0x1F1E6 + code.charCodeAt(0) - 65, 0x1F1E6 + code.charCodeAt(1) - 65);
    }

    TextMetrics { id: flagMetrics; font: root.theme.textFont; text: "🇬🇧" }
    RowLayout {
        id: content
        width: root.contentWidth
        height: Math.max(root.height, implicitHeight)
        spacing: root.cardGap
        Item {
            id: monthGrid
            readonly property real monthWidth: (width - root.cardGap) / 2
            readonly property real columnStride: monthWidth + root.cardGap
            readonly property int cellHeight: Math.max(30, Math.min(36, Math.round((monthWidth - 2 * root.cardPadding - 6 * root.daySpacing) / 7)))
            readonly property int monthHeight: 2 * root.cardPadding + root.monthHeadingHeight
                + root.monthHeadingSpacing + root.weekdayHeight + 6 * (cellHeight + root.daySpacing)
            readonly property int rowStride: monthHeight + root.cardGap
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.minimumWidth: root.minimumMonthWidth
            Layout.preferredWidth: root.preferredMonthWidth
            Layout.maximumWidth: root.preferredMonthWidth
            implicitHeight: rowStride + monthHeight

            function slotX(slot) {
                // The two offscreen slots extend the top row to the left and the bottom row to the right.
                const column = slot < 0 ? -1 : slot >= 4 ? 2 : slot % 2;
                return column * columnStride;
            }

            Item {
                anchors.fill: parent
                clip: true

                Item {
                    anchors.fill: parent
                    // Mask the stationary months where the moving month crosses between rows.
                    layer.enabled: root.monthDirection !== 0
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: false
                        maskEnabled: true; maskInverted: true; maskSource: crossingMask
                    }
                    Repeater {
                        id: months
                        property int created: 0
                        onItemAdded: created++
                        onItemRemoved: created--
                        model: 5
                        MonthSlide {
                            required property int index
                            monthIndex: index
                            visible: (!root.monthDirection || index !== 2) && x < monthGrid.width && x + width > 0
                        }
                    }
                }
                Item {
                    id: crossingMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: root.monthDirection !== 0
                    Rectangle {
                        x: crossingMonth.x - root.daySpacing
                        y: crossingMonth.y - root.daySpacing
                        width: crossingMonth.width + 2 * root.daySpacing
                        height: crossingMonth.height + 2 * root.daySpacing
                        color: "white"
                    }
                }
                MonthSlide {
                    id: crossingMonth
                    monthIndex: 2
                    visible: root.monthDirection !== 0
                }
            }
            MonthNavigation {
                id: previousMonth
                anchors { left: parent.left; top: parent.top; margins: root.cardPadding }
                icon: "chevron-left"
                hint: "Previous month"; onClicked: root.moveMonth(-1)
            }
            MonthNavigation {
                anchors { right: parent.right; top: parent.top; margins: root.cardPadding }
                icon: "chevron-right"
                hint: "Next month"; onClicked: root.moveMonth(1)
            }
        }

        ColumnLayout {
            id: sidebar
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.minimumWidth: root.sidebarMinimumWidth
            Layout.preferredWidth: 328
            visible: root.showSidebar
            spacing: root.cardGap

            Flickable {
                id: events
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(eventDays.implicitHeight, Math.max(160, monthGrid.implicitHeight
                    - (clocks.visible ? clocks.implicitHeight + sidebar.spacing : 0)))
                visible: root.agenda.configured
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: eventDays.implicitHeight
                ScrollBar.vertical: ScrollBar {}
                PillWheel { flickable: events }

                ColumnLayout {
                    id: eventDays
                    width: events.width
                    spacing: root.cardGap
                    HoverHandler {
                        blocking: false
                        onHoveredChanged: { if (!hovered) root.hoveredEvent = null; }
                    }
                    DayEvents { date: root.agenda.selectedDate }
                    DayEvents { date: root.agenda.nextDate }
                    Text {
                        font: root.theme.textFont; color: root.theme.secondary
                        Layout.fillWidth: true; wrapMode: Text.Wrap
                        visible: root.showCalendarWarning
                        text: "Some calendars are unavailable"
                    }
                }
            }

            CalendarCard {
                id: clocks
                Layout.fillWidth: true
                visible: root.agenda.clocks.length > 0
                implicitHeight: clockContents.implicitHeight + 2 * root.cardPadding
                ColumnLayout {
                    id: clockContents
                    anchors { fill: parent; topMargin: root.cardPadding; bottomMargin: root.cardPadding; leftMargin: 16; rightMargin: 16 }
                    spacing: 10
                    Repeater {
                        model: root.agenda.clocks
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                Layout.preferredWidth: Math.ceil(flagMetrics.advanceWidth)
                                font: root.theme.textFont; color: root.theme.text
                                text: root.countryFlag(modelData.country)
                                visible: root.showClockFlags
                            }
                            Text {
                                Layout.fillWidth: true; Layout.rightMargin: 7
                                font: root.theme.textFont; color: root.theme.overviewSecondary
                                text: modelData.name; textFormat: Text.PlainText; elide: Text.ElideRight
                            }
                            Text { font: root.theme.textFont; text: root.agenda.clockTime(modelData.offset); color: root.theme.overviewInk }
                        }
                    }
                }
            }
        }
    }

    component CalendarCard: Rectangle {
        property bool warm: false
        radius: 21.25
        color: warm ? Qt.alpha(root.theme.weatherTileTop, 0.58) : root.theme.overviewControls
        PillOverviewSurface {
            anchors.fill: parent
            theme: root.theme; radius: parent.radius
            frameOnly: true
            rimColor: "transparent"
            highlightColor: parent.warm ? root.theme.weatherHighlight : root.theme.overviewHighlight
        }
    }

    component MonthNavigation: ShellButton {
        theme: root.theme
        implicitWidth: root.monthHeadingHeight; implicitHeight: root.monthHeadingHeight
        iconSize: 22; radius: 12
        iconTint: root.theme.overviewInk
        color: hovered ? root.theme.overviewButtonHover : root.theme.overviewButton
    }

    component MonthSlide: CalendarMonth {
        required property int monthIndex
        readonly property int fromSlot: monthIndex - (root.monthDirection < 0 ? 1 : 0)
        readonly property int toSlot: monthIndex - (root.monthDirection > 0 ? 1 : 0)
        readonly property real row: (fromSlot < 2 ? 0 : 1) * (1 - root.monthProgress) + (toSlot < 2 ? 0 : 1) * root.monthProgress
        first: root.agenda.monthOffset(root.monthDirection > 0 ? root.transitionStart : root.agenda.rangeStart, monthIndex)
        cellHeight: monthGrid.cellHeight
        x: Math.round(monthGrid.slotX(fromSlot) * (1 - root.monthProgress) + monthGrid.slotX(toSlot) * root.monthProgress)
        y: Math.round(monthGrid.rowStride * row)
        width: monthGrid.monthWidth
        height: monthGrid.monthHeight
        enabled: !root.monthDirection
    }

    component CalendarMonth: Item {
        id: month
        required property date first
        required property int cellHeight
        readonly property var days: {
            const start = (first.getDay() + 6) % 7;
            return Array.from({length: 42}, (_, i) => new Date(first.getFullYear(), first.getMonth(), 1 - start + i));
        }
        readonly property Item selectedSlot: {
            const selected = root.agenda.selectedDate;
            if (selected.getFullYear() !== first.getFullYear() || selected.getMonth() !== first.getMonth()) return null;
            const index = (first.getDay() + 6) % 7 + selected.getDate() - 1;
            return index < cells.created ? cells.itemAt(index)?.emberSlot || null : null;
        }
        CalendarCard { anchors.fill: parent }
        ColumnLayout {
            anchors { fill: parent; margins: root.cardPadding }
            spacing: root.monthHeadingSpacing

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: root.monthHeadingHeight
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                font: root.theme.textFont; color: root.theme.overviewInk
                text: Qt.formatDateTime(month.first, "MMMM yyyy")
                opacity: {
                    if (!root.monthDirection || month.y >= previousMonth.y + previousMonth.height) return 1;
                    const left = month.x + (month.width - implicitWidth) / 2;
                    const right = monthGrid.width - left - implicitWidth;
                    return Math.max(0, Math.min(1, (Math.min(left, right) - previousMonth.x - previousMonth.width) / 12));
                }
            }
            GridLayout {
                id: grid
                Layout.fillWidth: true
                columns: 7; columnSpacing: root.daySpacing; rowSpacing: root.daySpacing
                uniformCellWidths: true
                Repeater {
                    model: ["M", "T", "W", "T", "F", "S", "S"]
                    Text {
                        required property string modelData
                        Layout.fillWidth: true; Layout.preferredHeight: root.weekdayHeight
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        font: root.theme.textFont; color: root.theme.overviewSecondary; text: modelData
                    }
                }
                Repeater {
                    id: cells
                    property int created: 0
                    onItemAdded: created++
                    onItemRemoved: created--
                    model: month.days
                    Item {
                        id: day
                        required property int index
                        required property var modelData
                        readonly property Item emberSlot: dateSlot
                        readonly property string key: root.agenda.dayKey(modelData)
                        readonly property bool inMonth: modelData.getMonth() === month.first.getMonth()
                        readonly property bool today: inMonth && key === root.todayKey
                        readonly property bool selected: inMonth && key === root.selectedKey
                        readonly property real highlightSize: Math.min(width, height)
                        readonly property int eventCount: inMonth ? root.agenda.eventsOn(key).length : 0
                        readonly property bool showSelection: selected && !root.hoveredEvent
                        readonly property real highlightedStart: {
                            const span = root.hoveredSpan;
                            if (!span || !inMonth) return Infinity;
                            const dayStart = modelData.getTime();
                            const nextDayStart = root.agenda.dayAfter(modelData).getTime();
                            let start = span.start < nextDayStart && span.end > dayStart ? span.start : Infinity;
                            if (span.uid) {
                                for (const event of root.agenda.eventsOn(key)) {
                                    if (event.calendarId === span.calendarId && root.seriesUid(event) === span.uid)
                                        start = Math.min(start, new Date(event.start).getTime());
                                }
                            }
                            return start;
                        }
                        readonly property bool continuesSpan: highlightedStart < modelData.getTime()
                        readonly property Item spanEnd: {
                            if (!Number.isFinite(highlightedStart)) return null;
                            const weekday = index % grid.columns;
                            if (weekday !== 0 && modelData.getDate() !== 1 && continuesSpan) return null;
                            // Join days only when an occurrence crosses midnight between them.
                            let last = day;
                            for (let i = index + 1; i <= index + grid.columns - weekday - 1; i++) {
                                const next = cells.itemAt(i);
                                if (!next?.continuesSpan) break;
                                last = next;
                            }
                            return last;
                        }
                        Layout.fillWidth: true; Layout.preferredHeight: month.cellHeight
                        opacity: inMonth ? 1 : 0.35

                        Rectangle {
                            anchors.centerIn: parent
                            width: day.highlightSize; height: width; radius: width / 2
                            color: day.showSelection ? (dateSlot.occupied ? "transparent" : root.theme.overviewAccent)
                                : dayHover.hovered ? root.theme.overviewButtonHover : "transparent"
                            border.width: day.today && !day.selected && !root.hoveredEvent ? 1 : 0
                            border.color: Qt.alpha(root.theme.overviewAccent, 0.5)
                        }
                        EmberSlot {
                            id: dateSlot
                            shell: root.shell; anchors.centerIn: parent
                            width: day.highlightSize; height: width
                        }
                        Text {
                            id: dateNumber
                            anchors.centerIn: parent; anchors.verticalCenterOffset: -2
                            font: root.theme.textFont; text: day.modelData.getDate()
                            color: day.showSelection && (!dateSlot.occupied || dateSlot.landed) ? root.theme.background : root.theme.overviewInk
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: dateNumber.bottom
                            visible: !root.hoveredEvent
                            spacing: 3
                            Repeater {
                                model: day.eventCount < 4 ? day.eventCount : day.eventCount === 4 ? 2 : 0
                                Rectangle { width: 3; height: 3; radius: 1.5; color: dateNumber.color }
                            }
                            Rectangle {
                                visible: day.eventCount >= 4
                                width: day.eventCount === 4 ? 10 : 16
                                height: 3; radius: 1.5; color: dateNumber.color
                            }
                        }
                        Rectangle {
                            anchors.top: dateNumber.bottom
                            readonly property real markerWidth: 16
                            x: (day.width - markerWidth) / 2
                            width: day.spanEnd ? day.spanEnd.x + day.spanEnd.width / 2 - day.x - x + markerWidth / 2 : 0
                            height: 3; radius: 1.5
                            visible: !!day.spanEnd
                            color: root.theme.overviewAccent
                        }
                        HoverHandler { id: dayHover; enabled: day.inMonth; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: day.inMonth; onTapped: root.agenda.selectDate(day.modelData) }
                    }
                }
            }
        }
    }

    component DayEvents: Item {
        id: dayEvents
        required property date date
        readonly property string key: root.agenda.dayKey(date)
        readonly property var entries: root.agenda.eventsOn(key)
        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: dayContents.implicitHeight + 2 * root.cardPadding
        CalendarCard {
            anchors.fill: parent
            warm: dayEvents.key === root.selectedKey
        }
        ColumnLayout {
            id: dayContents
            anchors { fill: parent; topMargin: root.cardPadding; bottomMargin: root.cardPadding; leftMargin: 16; rightMargin: 16 }
            spacing: 8
            Text { Layout.fillWidth: true; wrapMode: Text.Wrap; font: root.theme.textFont; text: root.dayHeading(dayEvents.date); color: root.theme.overviewInk }
            Text {
                font: root.theme.textFont; color: root.theme.overviewSecondary
                Layout.fillWidth: true; wrapMode: Text.Wrap
                visible: dayEvents.entries.length === 0
                text: root.emptyDayMessage(dayEvents.key)
            }
            Repeater {
                model: dayEvents.entries
                onItemRemoved: (index, item) => {
                    if (root.hoveredEvent === item) root.hoveredEvent = null;
                }
                RowLayout {
                    id: eventRow
                    required property var modelData
                    readonly property Item emberSlot: eventSlot
                    Layout.fillWidth: true; Layout.fillHeight: false; spacing: 12
                    EmberSlot {
                        id: eventSlot
                        shell: root.shell
                        implicitWidth: 3; Layout.fillHeight: true; shapeRadius: 1.5
                        Rectangle {
                            anchors.fill: parent; radius: 2
                            visible: !eventSlot.landed
                        color: root.hoveredEvent === eventRow ? root.theme.overviewAccent : root.theme.overviewSecondary
                        }
                    }
                    HoverHandler {
                        blocking: false
                        onHoveredChanged: { if (hovered) root.hoveredEvent = eventRow; }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 3
                        Text { font: root.theme.textFont; Layout.fillWidth: true; text: modelData.title; textFormat: Text.PlainText; color: root.theme.overviewInk; wrapMode: Text.Wrap }
                        Text { font: root.theme.textFont; text: root.eventTime(modelData); color: root.theme.overviewSecondary }
                    }
                }
            }
        }
    }
}
