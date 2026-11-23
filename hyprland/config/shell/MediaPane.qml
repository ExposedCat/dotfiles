import QtQuick

Flickable {
    id: root
    required property var shell
    required property var theme
    property Item firstPlayer: null
    readonly property Item emberTarget: firstPlayer?.playbackSlot || null
    implicitHeight: rows.implicitHeight
    contentHeight: rows.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight + bottomMargin > height
    flickableDirection: Flickable.VerticalFlick
    PillWheel { flickable: root }

    Column {
        id: rows
        width: root.width
        spacing: 10
        Repeater {
            model: root.shell.media.players
            onItemAdded: (index, item) => { if (index === 0) root.firstPlayer = item; }
            onItemRemoved: (index, item) => { if (item === root.firstPlayer) root.firstPlayer = null; }
            MediaStrip {
                required property var modelData
                width: rows.width; height: implicitHeight
                shell: root.shell; theme: root.theme; player: modelData
            }
        }
    }
}
