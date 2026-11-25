import QtQuick

// Each lip paints only its own exposed slice. Translucent layers never pile
// up under the front card or turn the stack into an opaque strip.
Item {
    id: root
    required property var theme
    property int count: 0
    readonly property int step: 6
    height: count * step
    Repeater {
        model: root.count
        Item {
            id: layer
            required property int index
            readonly property int depth: index + 1
            x: depth * 8; y: index * root.step
            width: root.width - depth * 16; height: root.step
            clip: true
            NotificationSurface {
                width: parent.width; height: 80
                y: parent.height - height
                theme: root.theme
                depth: layer.depth
            }
        }
    }
}
