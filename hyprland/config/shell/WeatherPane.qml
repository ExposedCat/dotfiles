import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root
    required property var shell
    required property var theme
    readonly property var weather: shell.weather
    readonly property bool pickingLocation: !weather.location || changingLocation
    readonly property Item emberTarget: pickingLocation ? null : locationArrowMarker
    readonly property bool hasSearched: !!weather.searchedQuery && query === weather.searchedQuery
    readonly property string query: search.text.trim()
    property bool changingLocation: false
    readonly property var daily: weather.forecast?.daily
    readonly property var weeklyRange: {
        const lows = (daily?.temperature_2m_min || []).filter(Number.isFinite);
        const highs = (daily?.temperature_2m_max || []).filter(Number.isFinite);
        return lows.length && highs.length ? {
            min: Math.min(...lows),
            span: Math.max(1, Math.max(...highs) - Math.min(...lows))
        } : {min: 0, span: 1};
    }
    implicitHeight: content.implicitHeight
    contentHeight: content.implicitHeight
    contentWidth: width
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    function focusSearch() {
        if (pickingLocation) search.forceActiveFocus();
    }

    function activate() {
        changingLocation = false;
        search.clear();
        contentY = 0;
        weather.refresh();
    }

    function choose(place) {
        weather.selectPlace(place);
        closeLocationPicker();
    }

    function closeLocationPicker() {
        changingLocation = false;
        search.clear();
        contentY = 0;
        locationButton.forceActiveFocus();
    }

    ColumnLayout {
        id: content
        width: root.width
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.pickingLocation
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: search
                    objectName: "weatherLocationSearch"
                    Layout.fillWidth: true
                    implicitHeight: 40
                    font: root.theme.textFont
                    color: root.theme.text
                    placeholderText: "City or postal code"
                    placeholderTextColor: root.theme.secondary
                    Accessible.name: placeholderText
                    maximumLength: 120
                    selectByMouse: true
                    leftPadding: 12
                    background: Rectangle { color: root.theme.surface; radius: 8 }
                    onAccepted: root.weather.findPlaces(root.query)
                }
                ShellButton {
                    theme: root.theme
                    text: "Search"
                    icon: "search"
                    enabled: root.query.length >= 2 && !root.weather.searching
                    onClicked: root.weather.findPlaces(root.query)
                }
                ShellButton {
                    objectName: "weatherLocationCancel"
                    visible: !!root.weather.location
                    theme: root.theme
                    text: "Cancel"
                    onClicked: root.closeLocationPicker()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: !root.hasSearched ? ""
                    : root.weather.searching ? "Searching…"
                    : root.weather.searchFailed ? "Location search failed. Try again."
                    : root.weather.places.length === 0 ? "No matching locations" : ""
                color: root.theme.secondary
                font: root.theme.textFont
                wrapMode: Text.Wrap
            }

            Repeater {
                model: root.pickingLocation && root.hasSearched && !root.weather.searching ? root.weather.places : []
                ShellButton {
                    required property var modelData
                    Layout.fillWidth: true
                    theme: root.theme
                    text: [modelData.name, root.weather.region(modelData, true)].filter(Boolean).join(" · ")
                    elideText: true
                    onClicked: root.choose(modelData)
                }
            }
        }

        PillOverviewSurface {
            Layout.fillWidth: true
            visible: !root.pickingLocation
            implicitHeight: conditions.implicitHeight + 26
            theme: root.theme
            radius: root.theme.overviewTileRadius
            weather: true

            ColumnLayout {
                id: conditions
                anchors { fill: parent; topMargin: 13; bottomMargin: 13; leftMargin: 15; rightMargin: 15 }
                spacing: 7
                Button {
                    id: locationButton
                    objectName: "weatherLocationButton"
                    Layout.alignment: Qt.AlignLeft
                    Layout.leftMargin: -7
                    Layout.maximumWidth: conditions.width + 7
                    leftPadding: 7
                    rightPadding: 7
                    topPadding: 3
                    bottomPadding: 3
                    hoverEnabled: true
                    text: {
                        const place = root.weather.location;
                        const region = place?.country || place?.admin1;
                        return region && region !== place.name ? place.name + ", " + region : place?.name ?? "";
                    }
                    Accessible.name: "Change weather location, " + text
                    background: Rectangle {
                        radius: 8
                        color: locationButton.hovered || locationButton.visualFocus ? root.theme.overviewButtonHover : "transparent"
                    }
                    contentItem: RowLayout {
                        spacing: 7
                        Text {
                            Layout.fillWidth: true; Layout.minimumWidth: 0
                            text: locationButton.text
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font: root.theme.textFont
                            color: root.theme.weatherAccent
                        }
                        ShellIcon {
                            name: "chevron-down"
                            Layout.preferredWidth: 16; Layout.preferredHeight: 16
                            tint: locationArrowMarker.landed ? root.theme.overviewAccent : root.theme.overviewSecondary
                            EmberSlot {
                                id: locationArrowMarker
                                anchors.fill: parent
                                shell: root.shell
                                shapeOpacity: 0
                            }
                        }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    onClicked: {
                        root.changingLocation = true;
                        root.contentY = 0;
                        root.focusSearch();
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !!root.weather.current
                    spacing: 12
                    WeatherIcon {
                        Layout.preferredWidth: 46; Layout.preferredHeight: 46
                        name: root.weather.day.icon
                        symbolicColor: root.theme.weatherIconColor(name)
                    }
                    Text {
                        text: root.weather.temperature(root.weather.current?.temperature_2m)
                        font.family: root.theme.fontFamily
                        font.pixelSize: 38
                        color: root.theme.text
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.weather.day.label
                        elide: Text.ElideRight
                        font: root.theme.textFont
                        color: root.theme.text
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !!root.weather.current
                    spacing: 8
                    Repeater {
                        model: [
                            ["Feels like", root.weather.temperature(root.weather.current?.apparent_temperature)],
                            ["Humidity", root.weather.rounded(root.weather.current?.relative_humidity_2m, "%")]
                        ]
                        Text {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData[0] + " " + modelData[1]
                            elide: Text.ElideRight
                            font: root.theme.textFont
                            color: root.theme.secondary
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: !root.pickingLocation && !!root.weather.current && forecast.count > 0
            implicitHeight: forecastRows.implicitHeight + 14
            radius: 18
            color: root.theme.overviewControls
            ColumnLayout {
                id: forecastRows
                readonly property int dateWidth: Math.ceil(Math.max(0, ...children.map(row => row.dateTextWidth ?? 0)))
                readonly property int rainWidth: Math.ceil(Math.max(0, ...children.map(row => row.rainTextWidth ?? 0)))
                readonly property int temperatureWidth: Math.ceil(Math.max(0, ...children.map(row => row.temperatureTextWidth ?? 0)))
                anchors { fill: parent; margins: 7 }
                spacing: 0
                Repeater {
                    id: forecast
                    model: root.daily?.time || []
                    Item {
                        id: day
                        required property int index
                        required property string modelData
                        readonly property var condition: root.weather.condition(root.daily?.weather_code?.[index], true)
                        readonly property real low: root.daily?.temperature_2m_min?.[index] ?? NaN
                        readonly property real high: root.daily?.temperature_2m_max?.[index] ?? NaN
                        readonly property real dateTextWidth: dateLabel.implicitWidth
                        readonly property real rainTextWidth: rainLabel.implicitWidth
                        readonly property real temperatureTextWidth: Math.max(lowLabel.implicitWidth, highLabel.implicitWidth)
                        Layout.fillWidth: true
                        implicitHeight: fields.implicitHeight + 12
                        Rectangle {
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            height: 1; visible: day.index > 0; color: root.theme.overviewHighlight
                        }
                        RowLayout {
                            id: fields
                            anchors { left: parent.left; right: parent.right; margins: 5; verticalCenter: parent.verticalCenter }
                            spacing: width >= 440 ? 16 : 9
                            Text {
                                id: dateLabel
                                Layout.preferredWidth: forecastRows.dateWidth
                                text: Qt.formatDateTime(new Date(day.modelData + "T12:00:00"), "ddd d")
                                font: root.theme.textFont; color: root.theme.overviewInk
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                WeatherIcon {
                                    Layout.preferredWidth: 22; Layout.preferredHeight: 22
                                    name: day.condition.icon; symbolicColor: root.theme.weatherIconColor(name)
                                }
                                Text {
                                    Layout.fillWidth: true; Layout.minimumWidth: 0
                                    text: day.condition.label; elide: Text.ElideRight
                                    font: root.theme.textFont; color: root.theme.overviewSecondary
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: false
                                spacing: 6
                                Text {
                                    id: rainLabel
                                    Layout.preferredWidth: forecastRows.rainWidth
                                    text: root.weather.rounded(root.daily?.precipitation_probability_max?.[day.index], "%")
                                    Accessible.name: "Chance of precipitation " + text
                                    horizontalAlignment: Text.AlignRight
                                    font: root.theme.textFont; color: root.theme.overviewSecondary
                                }
                                ShellIcon {
                                    name: "droplets"; tint: root.theme.overviewSecondary
                                    Layout.preferredWidth: 16; Layout.preferredHeight: 16
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: false
                                spacing: 9
                                Text {
                                    id: lowLabel
                                    Layout.preferredWidth: forecastRows.temperatureWidth
                                    text: root.weather.rounded(day.low, "°")
                                    horizontalAlignment: Text.AlignRight
                                    font: root.theme.textFont; color: root.theme.overviewSecondary
                                }
                                Rectangle {
                                    Layout.preferredWidth: 60; Layout.minimumWidth: 18; Layout.preferredHeight: 4
                                    radius: 2; color: root.theme.overviewButtonHover
                                    Rectangle {
                                        visible: Number.isFinite(day.low) && Number.isFinite(day.high)
                                        x: visible ? parent.width * (day.low - root.weeklyRange.min) / root.weeklyRange.span : 0
                                        width: visible ? Math.min(parent.width - x, Math.max(3, parent.width * (day.high - day.low) / root.weeklyRange.span)) : 0
                                        height: parent.height; radius: 2; color: root.theme.overviewAccent
                                    }
                                }
                                Text {
                                    id: highLabel
                                    Layout.preferredWidth: forecastRows.temperatureWidth
                                    text: root.weather.rounded(day.high, "°")
                                    horizontalAlignment: Text.AlignRight
                                    font: root.theme.textFont; color: root.theme.overviewInk
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.pickingLocation && (root.weather.unavailable || !root.weather.current || root.weather.saveFailed)
            Text {
                Layout.fillWidth: true
                text: root.weather.saveFailed ? "Could not save the location"
                    : root.weather.loading ? "Loading weather…"
                    : root.weather.current ? "Showing the last available forecast" : "Weather unavailable"
                font: root.theme.textFont
                color: root.theme.secondary
                wrapMode: Text.Wrap
            }
            ShellButton {
                theme: root.theme
                visible: !root.weather.loading
                text: "Retry"
                onClicked: {
                    if (root.weather.saveFailed) root.weather.persist();
                    root.weather.refresh(true);
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: root.pickingLocation
            text: 'Location data by <a href="https://www.geonames.org/">GeoNames</a> · Weather data by <a href="https://open-meteo.com/en//license">Open-Meteo</a>'
            textFormat: Text.StyledText
            wrapMode: Text.WordWrap
            color: root.theme.secondary
            linkColor: root.theme.secondary
            font.family: root.theme.fontFamily
            font.pixelSize: 14
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }
}
