import QtQuick
import QtQuick.Shapes

// Broad concave shoulders flow into the original rounded drop body.
Shape {
    id: root
    property color color: "#000000"
    property real wing: 12
    readonly property real bodyWidth: Math.max(0, width - wing * 2)
    readonly property real shoulder: wing + Math.min(12, bodyWidth / 8)
    readonly property real corner: Math.min(22, height / 2, bodyWidth / 4)
    readonly property real shoulderHeight: Math.min(14, height - corner)
    antialiasing: true
    ShapePath {
        strokeWidth: 0
        fillColor: root.color
        startX: 0; startY: 0
        PathLine { x: root.width; y: 0 }
        PathCubic { x: root.width - root.shoulder; y: root.shoulderHeight; control1X: root.width - root.shoulder * 0.35; control1Y: 0; control2X: root.width - root.shoulder; control2Y: root.shoulderHeight / 2 }
        PathLine { x: root.width - root.shoulder; y: root.height - root.corner }
        PathQuad { x: root.width - root.shoulder - root.corner; y: root.height; controlX: root.width - root.shoulder; controlY: root.height }
        PathLine { x: root.shoulder + root.corner; y: root.height }
        PathQuad { x: root.shoulder; y: root.height - root.corner; controlX: root.shoulder; controlY: root.height }
        PathLine { x: root.shoulder; y: root.shoulderHeight }
        PathCubic { x: 0; y: 0; control1X: root.shoulder; control1Y: root.shoulderHeight / 2; control2X: root.shoulder * 0.35; control2Y: 0 }
    }
}
