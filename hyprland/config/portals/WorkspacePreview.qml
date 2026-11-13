import QtQuick

Item {
    id: root
    property var sourceData: ({})
    property var theme
    property bool fixture: false
    readonly property bool hasContent: !!(sourceData.tiles && sourceData.tiles.length)
    Rectangle {
        id: desktop
        anchors.centerIn: parent
        width: Math.min(parent.width - 10, (parent.height - 10) * (root.sourceData.aspect || 16 / 9))
        height: width / (root.sourceData.aspect || 16 / 9)
        radius: 5
        color: "#171b20"
        gradient: Gradient { GradientStop { position: 0; color: "#1a222c" } GradientStop { position: 1; color: "#101215" } }
        Repeater {
            model: root.sourceData.tiles || []
            Item {
                id: tile
                required property var modelData
                x: modelData.x * desktop.width; y: modelData.y * desktop.height
                width: modelData.width * desktop.width; height: modelData.height * desktop.height
                clip: true
                SourcePreview { anchors.fill: parent; anchors.margins: 1; sourceData: tile.modelData; theme: root.theme; fixture: root.fixture }
            }
        }
    }
}
