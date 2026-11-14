import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    readonly property var media: shell.media
    readonly property Item emberTarget: media.player && media.player.canSeek && media.length > 0 ? seek.emberSlot : null
    spacing: 16
    RowLayout {
        Layout.fillWidth: true; spacing: 20
        Rectangle {
            Layout.preferredWidth: 112; Layout.preferredHeight: 112
            radius: 14; color: root.theme.surface; clip: true
            Image { id: art; anchors.fill: parent; source: root.shell.panel === "media" && root.media.player ? root.media.player.trackArtUrl || "" : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 224; sourceSize.height: 224; visible: status === Image.Ready }
            Text { anchors.centerIn: parent; visible: !art.visible; text: "♫"; font.pixelSize: 42; color: root.theme.accent }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 8
            Text { Layout.fillWidth: true; text: root.media.title; textFormat: Text.PlainText; color: root.theme.text; font.family: root.theme.fontFamily; font.pixelSize: 22; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; text: root.media.artist; textFormat: Text.PlainText; color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; text: root.media.player ? root.media.player.trackAlbum || "" : ""; textFormat: Text.PlainText; color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; elide: Text.ElideRight }
        }
    }
    PillComboBox {
        theme: root.theme
        Layout.fillWidth: true; visible: root.media.players.length > 1
        model: root.media.players.map(p => p.identity)
        currentIndex: Math.max(0, root.media.players.indexOf(root.media.player))
        onActivated: root.media.selected = root.media.players[currentIndex].dbusName
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize
        Accessible.name: "Media player"
    }
    PillSlider {
        id: seek
        emberShell: root.shell
        Layout.fillWidth: true; theme: root.theme
        to: Math.max(1, root.media.length); backendValue: root.media.position
        enabled: !!(root.media.player && root.media.player.canSeek && root.media.length > 0)
        onMoved: root.media.action("seek", value)
        Accessible.name: "Playback position"
    }
    RowLayout {
        Layout.fillWidth: true
        Text { text: root.media.time(seek.value); color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize }
        Item { Layout.fillWidth: true }
        ShellButton { theme: root.theme; icon: "skip-back"; hint: "Previous track"; enabled: !!(root.media.player && root.media.player.canGoPrevious); onClicked: root.media.action("previous") }
        ShellButton { theme: root.theme; icon: root.media.playing ? "pause" : "play"; hint: root.media.playing ? "Pause" : "Play"; enabled: !!(root.media.player && root.media.player.canTogglePlaying); onClicked: root.media.action("toggle") }
        ShellButton { theme: root.theme; icon: "skip-forward"; hint: "Next track"; enabled: !!(root.media.player && root.media.player.canGoNext); onClicked: root.media.action("next") }
        Item { Layout.fillWidth: true }
        Text { text: root.media.time(root.media.length); color: root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize }
    }
    Item { Layout.fillHeight: true }
}
