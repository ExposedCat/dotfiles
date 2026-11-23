import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property var shell
    required property var theme
    required property var player
    property bool showPlayerList: false
    signal playerListRequested()
    readonly property bool playing: shell.media.isPlaying(player)
    readonly property real duration: Math.max(0, player?.length || 0)
    readonly property int coverSize: width < 372 ? 50 : 68
    Accessible.name: player?.identity || "Media player"
    implicitHeight: Math.max(coverSize, body.implicitHeight) + 18
    radius: 18
    color: theme.overviewControls

    RowLayout {
        anchors { fill: parent; leftMargin: 11; rightMargin: 11; topMargin: 9; bottomMargin: 9 }
        spacing: root.coverSize === 68 ? 18 : 10
        Rectangle {
            Layout.preferredWidth: root.coverSize; Layout.preferredHeight: root.coverSize
            Layout.alignment: Qt.AlignVCenter
            radius: 13; color: root.theme.overviewButton; clip: true
            Image {
                id: art
                anchors.fill: parent
                source: root.visible ? root.player?.trackArtUrl || "" : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 2 * root.coverSize; sourceSize.height: 2 * root.coverSize
                visible: status === Image.Ready
            }
            ShellIcon { anchors.centerIn: parent; name: "music"; tint: root.theme.overviewSecondary; width: 26; height: 26; visible: !art.visible }
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.alignment: Qt.AlignVCenter
            spacing: 3
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 0
                    Text {
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        text: root.player?.trackTitle || root.player?.identity || ""
                        textFormat: Text.PlainText; elide: Text.ElideRight; font: root.theme.textFont; color: root.theme.overviewInk
                    }
                    Text {
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        text: root.player?.trackArtist || (root.player?.trackTitle ? root.player?.identity || "" : "")
                        visible: text.length > 0
                        textFormat: Text.PlainText; elide: Text.ElideRight; font: root.theme.textFont; color: root.theme.overviewSecondary
                    }
                }
                Row {
                    spacing: 2
                    Transport {
                        icon: "skip-back"; hint: "Previous track"
                        visible: !!root.player?.canGoPrevious
                        onClicked: root.shell.media.action(root.player, "previous")
                    }
                    Transport {
                        icon: root.playing ? "pause" : "play"
                        hint: (root.playing ? "Pause " : "Play ") + (root.player?.identity || "media")
                        selected: root.playing
                        enabled: !!root.player?.canTogglePlaying
                        onClicked: root.shell.media.action(root.player, "toggle")
                    }
                    Transport {
                        icon: "skip-forward"; hint: "Next track"
                        visible: !!root.player?.canGoNext
                        onClicked: root.shell.media.action(root.player, "next")
                    }
                    Transport {
                        visible: root.showPlayerList
                        icon: "layers"; hint: "Show all media players"
                        onClicked: root.playerListRequested()
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                visible: root.duration > 0
                Text {
                    text: root.shell.media.time(seek.value)
                    color: root.theme.overviewSecondary
                    font: root.theme.textFont
                }
                MediaSeekSlider {
                    id: seek
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    trackKey: [root.player?.dbusName, root.player?.trackTitle, root.player?.trackArtist].join("\n")
                    to: Math.max(1, root.duration)
                    backendValue: Math.min(to, root.shell.media.positionOf(root.player))
                    enabled: !!root.player?.canSeek && root.duration > 0
                    onSeekRequested: position => root.shell.media.action(root.player, "seek", position)
                }
                Text { text: root.shell.media.time(root.duration); color: root.theme.overviewSecondary; font: root.theme.textFont }
            }
        }
    }

    component Transport: ShellButton {
        theme: root.theme
        width: root.coverSize === 68 ? 33 : 29; height: 34
        radius: 10; iconSize: 18
        iconTint: selected ? root.theme.overviewAccent : root.theme.overviewInk
        color: hovered ? root.theme.overviewButtonHover : selected ? Qt.alpha(root.theme.overviewAccent, 0.12) : "transparent"
    }
}
