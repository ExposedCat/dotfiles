import QtQuick
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
    readonly property int gap: 14
    readonly property int footerSpacing: 6
    readonly property int footerHeight: 42
    readonly property int controlSize: 54
    readonly property int controlPadding: 9
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
    implicitHeight: actionsHeight + footerSpacing + footerHeight

    ShellButton {
        id: weatherTile
        objectName: "pillWeatherButton"
        theme: root.theme
        width: Math.max(0, controlsSurface.x - root.gap)
        height: root.actionsHeight
        radius: 21.25
        hint: root.shell.weather.summary
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
                width: parent.width; height: 21
                Text {
                    id: city
                    anchors { left: parent.left; right: forecastArrow.left; rightMargin: 6 }
                    text: root.shell.weather.location?.name || "Weather"
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: root.theme.fontFamily
                    font.weight: Font.Medium
                    font.pixelSize: 16
                    color: root.theme.weatherAccent
                }
                ShellIcon {
                    id: forecastArrow
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 17.5; height: 17.5
                    name: "arrow-up-right"
                    tint: root.theme.weatherAccent
                    opacity: 0.9
                }
            }
            Row {
                height: 44.5; spacing: 11
                ShellIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22
                    name: root.weatherIcons[root.shell.weather.day.icon] ?? "cloud-sun"
                    tint: root.theme.weatherIcon
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
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
            }
            Text {
                width: parent.width
                text: root.shell.weather.current ? root.shell.weather.day.label
                    : root.shell.weather.location ? root.shell.weather.summary : "Set location"
                elide: Text.ElideRight
                height: 21
                font.family: root.theme.fontFamily
                font.pixelSize: 16
                color: root.theme.weatherCondition
            }
        }
    }

    WorkspaceDots {
        id: workspaceWidget
        x: 14; y: root.actionsHeight + root.footerSpacing
        height: root.footerHeight
        dot: 6; gap: 17; minimumActiveWidth: 26
        activeColor: root.theme.overviewAccent
        inactiveColor: root.theme.overviewDot
        shell: root.shell; theme: root.theme; spaces: root.spaces; floating: true
    }

    component Control: ShellButton {
        readonly property bool highlighted: hovered || (root.shell.emberEnabled && root.shell.emberTarget === emberSlot)
        theme: root.theme
        width: root.controlSize; height: root.controlSize
        radius: 16.25
        iconSize: 23
        iconTint: danger ? root.theme.overviewPowerInk : root.theme.overviewInk
        color: highlighted ? root.theme.overviewButtonHover : danger ? root.theme.overviewPowerFill : root.theme.overviewButton
        emberSlot.shapeOpacity: 0
    }

    Rectangle {
        id: controlsSurface
        objectName: "pillRightControls"
        anchors.right: parent.right
        width: controlGrid.width + 2 * root.controlPadding
        height: controlGrid.implicitHeight + 2 * root.controlPadding
        radius: 21.25
        color: root.theme.overviewControls
        Grid {
            id: controlGrid
            objectName: "pillControlButtons"
            x: root.controlPadding; y: root.controlPadding
            columns: 3; spacing: 6
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
                objectName: "pillMusicButton"
                visible: !!root.shell.media.player
                icon: "music"; hint: "Now playing"; onClicked: root.panelRequested("media")
            }
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

    Flickable {
        anchors { right: parent.right; rightMargin: 4 }
        y: root.actionsHeight + root.footerSpacing
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
