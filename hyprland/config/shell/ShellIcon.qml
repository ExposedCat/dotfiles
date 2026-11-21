import QtQuick
import QtQuick.Effects

Image {
    id: root
    property string name: ""
    property color tint: "transparent"
    width: 18
    height: 18
    source: name ? Qt.resolvedUrl("icons/" + name + ".svg") : ""
    sourceSize.width: width
    sourceSize.height: height
    fillMode: Image.PreserveAspectFit
    layer.enabled: tint.a > 0
    layer.effect: MultiEffect { contrast: -1; brightness: 0.5; colorization: 1; colorizationColor: root.tint }
}
