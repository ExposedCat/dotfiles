import QtQuick

Flickable {
    id: root
    required property var shell
    required property var theme
    implicitHeight: rows.implicitHeight
    contentHeight: rows.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    flickableDirection: Flickable.VerticalFlick
    PillWheel { flickable: root }

    Column {
        id: rows
        width: root.width
        spacing: 10
        Repeater {
            model: root.shell.media.players
            MediaStrip {
                required property var modelData
                width: rows.width; height: implicitHeight
                shell: root.shell; theme: root.theme; player: modelData
            }
        }
    }
}
