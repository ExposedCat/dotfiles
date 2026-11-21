import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root
    required property var shell
    required property var theme
    readonly property var weather: shell.weather
    readonly property bool pickingLocation: !weather.location || changingLocation
    readonly property bool hasSearched: !!weather.searchedQuery && query === weather.searchedQuery
    readonly property string query: search.text.trim()
    property bool changingLocation: false
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
        changingLocation = false;
        search.clear();
        contentY = 0;
        locationButton.forceActiveFocus();
    }

    ColumnLayout {
        id: content
        width: root.width
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: root.pickingLocation ? "Weather location" : root.weather.location.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.theme.text
                font.family: root.theme.fontFamily
                font.pixelSize: 24
            }
            ShellButton {
                id: locationButton
                objectName: "weatherLocationButton"
                visible: !!root.weather.location
                theme: root.theme
                text: root.pickingLocation ? "Cancel" : "Change location"
                onClicked: {
                    root.changingLocation = !root.changingLocation;
                    search.clear();
                    root.contentY = 0;
                    if (root.pickingLocation) root.focusSearch();
                }
            }
        }

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

        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.pickingLocation && !!root.weather.current
            spacing: 7

            Text {
                Layout.fillWidth: true
                text: root.weather.location ? root.weather.region(root.weather.location) : ""
                textFormat: Text.PlainText
                visible: text.length > 0
                elide: Text.ElideRight
                font: root.theme.textFont
                color: root.theme.secondary
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                WeatherIcon {
                    Layout.preferredWidth: 42; Layout.preferredHeight: 42
                    name: root.weather.day.icon
                    symbolicColor: root.theme.text
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
                spacing: 8
                Repeater {
                    model: [
                        ["Feels like", root.weather.temperature(root.weather.current?.apparent_temperature)],
                        ["Humidity", root.weather.rounded(root.weather.current?.relative_humidity_2m, "%")],
                        ["Wind", root.weather.rounded(root.weather.current?.wind_speed_10m, " km/h")]
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

            Rectangle { Layout.fillWidth: true; Layout.topMargin: 6; implicitHeight: 1; color: Qt.alpha(root.theme.border, 0.4) }

            RowLayout {
                Layout.fillWidth: true
                Text { Layout.fillWidth: true; text: "7-day forecast"; color: root.theme.text; font: root.theme.textFont }
                Text { Layout.minimumWidth: 82; text: "Precip."; color: root.theme.secondary; font: root.theme.textFont; horizontalAlignment: Text.AlignRight }
                Text { Layout.minimumWidth: 104; text: "Low / High"; color: root.theme.secondary; font: root.theme.textFont; horizontalAlignment: Text.AlignRight }
            }

            Repeater {
                model: root.weather.forecast?.daily?.time || []
                RowLayout {
                    required property int index
                    required property string modelData
                    readonly property var daily: root.weather.forecast?.daily
                    readonly property var condition: root.weather.condition(daily?.weather_code?.[index], true)
                    Layout.fillWidth: true
                    spacing: 7
                    Text {
                        Layout.minimumWidth: 75
                        text: Qt.formatDateTime(new Date(modelData + "T12:00:00"), "ddd d")
                        font: root.theme.textFont
                        color: root.theme.text
                    }
                    WeatherIcon {
                        Layout.preferredWidth: 20; Layout.preferredHeight: 20
                        name: parent.condition.icon
                        symbolicColor: root.theme.text
                    }
                    Text {
                        Layout.fillWidth: true
                        text: parent.condition.label
                        elide: Text.ElideRight
                        font: root.theme.textFont
                        color: root.theme.secondary
                    }
                    Text {
                        Layout.minimumWidth: 82
                        text: root.weather.rounded(daily?.precipitation_probability_max?.[index], "%")
                        horizontalAlignment: Text.AlignRight
                        font: root.theme.textFont
                        color: root.theme.secondary
                    }
                    Text {
                        Layout.minimumWidth: 104
                        text: root.weather.rounded(daily?.temperature_2m_min?.[index], "°") + " / " + root.weather.rounded(daily?.temperature_2m_max?.[index], "°")
                        horizontalAlignment: Text.AlignRight
                        font: root.theme.textFont
                        color: root.theme.text
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
            Layout.topMargin: 4
            visible: root.pickingLocation || !!root.weather.current
            text: root.pickingLocation ? 'Location data by <a href="https://www.geonames.org/">GeoNames</a>'
                : 'Forecast by <a href="https://open-meteo.com/">Open-Meteo</a>'
            textFormat: Text.StyledText
            color: root.theme.secondary
            linkColor: root.theme.secondary
            font.family: root.theme.fontFamily
            font.pixelSize: 14
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }
}
