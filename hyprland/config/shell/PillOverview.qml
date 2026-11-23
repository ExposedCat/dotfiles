import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray

Item {
    id: root
    required property var shell
    required property var theme
    required property var spaces
    signal panelRequested(string name)
    signal trayMenuRequested(var trayItem, Item trayAnchor)

    readonly property Item workspaceSlot: workspaceWidget.emberSlot
    readonly property real actionsHeight: controlsSurface.height
    readonly property int gap: theme.overviewGap
    readonly property int footerSpacing: 6
    readonly property int footerHeight: 42
    readonly property int controlSize: theme.overviewControlSize
    readonly property int controlPadding: theme.overviewControlPadding
    readonly property int trayIconWidth: 42
    readonly property var weatherIcons: ({
        "weather-clear-symbolic": "sun",
        "weather-clear-night-symbolic": "moon",
        "weather-few-clouds-symbolic": "cloud-sun",
        "weather-few-clouds-night-symbolic": "cloud-moon",
        "weather-overcast-symbolic": "cloud",
        "weather-fog-symbolic": "cloud-fog",
        "weather-showers-scattered-symbolic": "cloud-drizzle",
        "weather-freezing-rain-symbolic": "cloud-hail",
        "weather-showers-symbolic": "cloud-rain",
        "weather-snow-symbolic": "cloud-snow",
        "weather-storm-symbolic": "cloud-lightning"
    })
    implicitWidth: Math.max(444, workspaceWidget.x + workspaceWidget.implicitWidth + gap + controlsSurface.width)
    readonly property real footerTop: actionsHeight + (mediaStrip.player ? gap + mediaStrip.height : 0) + footerSpacing
    implicitHeight: footerTop + footerHeight

    ShellButton {
        id: weatherTile
        objectName: "pillWeatherButton"
        theme: root.theme
        width: Math.max(0, controlsSurface.x - root.gap)
        height: root.actionsHeight
        radius: root.theme.overviewTileRadius
        hint: root.shell.weather.summary
        // The tile owns hover and focus, and the arrow owns the landing.
        emberSlot.parent: forecastArrow
        emberSlot.shapeOpacity: 0
        onClicked: root.panelRequested("weather")

        PillOverviewSurface {
            anchors.fill: parent
            z: -1
            enabled: false
            theme: root.theme
            weather: true
            radius: weatherTile.radius
            highlighted: weatherTile.hovered || (root.shell.emberEnabled && root.shell.emberTarget === weatherTile.emberSlot)
        }

        Column {
            anchors { left: parent.left; right: parent.right; margins: 16; verticalCenter: parent.verticalCenter }
            spacing: 5

            Item {
                width: parent.width; height: city.implicitHeight
                Text {
                    id: city
                    anchors { left: parent.left; right: forecastArrow.left; rightMargin: 6 }
                    text: root.shell.weather.location?.name || "Weather"
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.weight: Font.Medium
                    font.pixelSize: root.theme.bodySize
                    color: root.theme.weatherAccent
                }
                ShellIcon {
                    id: forecastArrow
                    readonly property Item marker: weatherTile.emberSlot
                    readonly property real fillProgress: !marker.occupied ? 0 : marker.landed ? 1
                        : marker.motion?.phase === "landing" ? 1 - marker.motion.pose.alpha : 0
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 17.5; height: 17.5
                    name: "arrow-up-right"
                    tint: Qt.tint(root.theme.weatherAccent, Qt.alpha(root.theme.overviewAccent, fillProgress))
                    opacity: 0.9
                    Behavior on tint {
                        enabled: !forecastArrow.marker.occupied
                        ColorAnimation { duration: 100 }
                    }
                }
            }
            RowLayout {
                width: parent.width
                height: Math.max(44.5, implicitHeight)
                spacing: 8
                ShellIcon {
                    Layout.preferredWidth: 32; Layout.preferredHeight: 32
                    name: root.weatherIcons[root.shell.weather.day.icon] ?? "cloud-sun"
                    tint: root.theme.weatherIconColor(root.shell.weather.day.icon)
                }
                Text {
                    Layout.alignment: Qt.AlignBaseline
                    visible: !!root.shell.weather.current
                    text: Number.isFinite(root.shell.weather.current?.temperature_2m)
                        ? root.shell.weather.rounded(root.shell.weather.current.temperature_2m, "")
                            + '<font color="' + root.theme.weatherAccent + '">°</font>'
                        : "—"
                    textFormat: Text.StyledText
                    font.family: root.theme.fontFamily
                    font.features: root.theme.textFont.features
                    font.pixelSize: 41
                    font.letterSpacing: -1.25
                    color: root.theme.overviewInk
                }
                Text {
                    readonly property real apparent: root.shell.weather.current?.apparent_temperature ?? NaN
                    Layout.alignment: Qt.AlignBaseline
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    visible: Number.isFinite(apparent)
                    text: visible ? root.shell.weather.rounded(apparent, "°") : ""
                    Accessible.name: visible ? "Feels like " + text : ""
                    elide: Text.ElideRight
                    font: root.theme.textFont
                    color: root.theme.weatherCondition
                }
            }
            Text {
                width: parent.width
                text: root.shell.weather.current ? root.shell.weather.day.label
                    : root.shell.weather.location ? root.shell.weather.summary : "Set location"
                elide: Text.ElideRight
                font: root.theme.textFont
                color: root.theme.weatherCondition
            }
        }
    }

    WorkspaceDots {
        id: workspaceWidget
        x: 14; y: root.footerTop
        height: root.footerHeight
        dot: 6; gap: 17; minimumActiveWidth: 26
        inactiveColor: root.theme.overviewDot
        shell: root.shell; theme: root.theme; spaces: root.spaces; floating: true
    }

    component Control: PillControl {
        theme: root.theme
        width: root.controlSize; height: root.controlSize
    }

    Rectangle {
        id: controlsSurface
        objectName: "pillRightControls"
        anchors.right: parent.right
        width: controlGrid.width + 2 * root.controlPadding
        height: controlGrid.implicitHeight + 2 * root.controlPadding
        radius: root.theme.overviewTileRadius
        color: root.theme.overviewControls
        Grid {
            id: controlGrid
            objectName: "pillControlButtons"
            x: root.controlPadding; y: root.controlPadding
            columns: 3; spacing: root.theme.overviewControlGap
            width: columns * root.controlSize + (columns - 1) * spacing
            Control {
                objectName: "pillAppearanceButton"
                icon: root.shell.appearance.dark ? "moon" : "sun"
                hint: root.shell.appearance.error || (root.shell.appearance.dark ? "Switch to light style" : "Switch to dark style")
                enabled: root.shell.appearance.available && !root.shell.appearance.pending
                onClicked: root.shell.appearance.toggle()
            }
            Control {
                icon: root.shell.audio.muted ? "volume-x" : "volume-2"
                hint: "Sound"; onClicked: root.panelRequested("mixer")
                onScrolled: delta => root.shell.audio.adjust(delta > 0 ? 0.05 : -0.05)
            }
            Control { icon: "activity"; hint: "System statistics"; onClicked: root.panelRequested("system") }
            Control { icon: "ethernet-port"; hint: "Network"; onClicked: root.panelRequested("ethernet") }
            Control {
                objectName: "pillBluetoothButton"
                icon: root.shell.bluetooth.enabled ? "bluetooth" : "bluetooth-off"
                hint: "Bluetooth"; onClicked: root.panelRequested("bluetooth")
            }
            Control { icon: "power"; hint: "Power"; danger: true; onClicked: root.panelRequested("power") }
            Control {
                objectName: "pillOverviewMicrophone"
                visible: root.shell.audio.micInUse
                icon: root.shell.audio.activeMicsMuted ? "mic-off" : "mic"
                hint: root.shell.audio.activeMicsMuted ? "Unmute microphone" : "Mute microphone"
                onClicked: root.shell.audio.toggleActiveMics()
            }
            Control {
                objectName: "pillOverviewScreenSharing"
                visible: root.shell.screenSharing
                icon: "screen-share"; hint: "Stop screen sharing"
                onClicked: root.shell.stopScreenSharing()
            }
        }
    }

    MediaStrip {
        id: mediaStrip
        objectName: "pillMediaStrip"
        y: root.actionsHeight + root.gap
        width: root.width; height: implicitHeight
        visible: !!player
        shell: root.shell; theme: root.theme; player: root.shell.media.player
        showPlayerList: root.shell.media.players.length > 1
        onPlayerListRequested: root.panelRequested("media")
    }

    Flickable {
        anchors { right: parent.right; rightMargin: 4 }
        y: root.footerTop
        width: Math.min(trayIcons.implicitWidth, controlsSurface.width - anchors.rightMargin)
        height: root.footerHeight
        contentWidth: trayIcons.implicitWidth; contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        acceptedButtons: Qt.LeftButton
        interactive: contentWidth > width
        clip: true
        Row {
            id: trayIcons
            height: root.footerHeight; spacing: 2
            Repeater {
                model: root.shell.fixture ? [] : SystemTray.items
                Item {
                    id: tray
                    required property var modelData
                    implicitWidth: root.trayIconWidth; implicitHeight: root.footerHeight
                    Rectangle {
                        anchors.fill: parent
                        radius: 12.5
                        color: trayPointer.containsMouse ? root.theme.overviewButtonHover : "transparent"
                    }
                    Image {
                        anchors.centerIn: parent
                        width: 20; height: 20; sourceSize.width: 20; sourceSize.height: 20
                        source: tray.modelData.icon
                    }
                    MouseArea {
                        id: trayPointer
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: event => {
                            if (event.button === Qt.RightButton || tray.modelData.onlyMenu)
                                root.trayMenuRequested(tray.modelData, tray);
                            else if (event.button === Qt.MiddleButton) tray.modelData.secondaryActivate();
                            else tray.modelData.activate();
                        }
                        onWheel: event => tray.modelData.scroll(event.angleDelta.y, false)
                    }
                }
            }
        }
    }
}
