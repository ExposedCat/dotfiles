import QtQuick
import QtQuick.Shapes

// One outline: the panel drop's upper edge stays fixed while its rounded foot
// spreads into the popup. Its full-width base extends below neighboring drops
// before spreading. Flush outer edges have neither a flare nor an upper corner.
Shape {
    id: root
    required property real originX
    required property real originWidth
    required property real panelHeight
    required property rect targetRect
    property real progress: 0
    property color color: "black"
    property real wing: 12
    readonly property real shoulder: wing + Math.min(12, Math.max(0, originWidth - wing * 2) / 8)
    readonly property real closedCorner: Math.min(22, panelHeight / 2, Math.max(0, originWidth - wing * 2) / 4)
    readonly property real shoulderHeight: Math.min(14, panelHeight - closedCorner)
    readonly property real sourceLeft: originX + shoulder
    readonly property real sourceRight: originX + originWidth - shoulder
    readonly property real spread: Math.pow(Math.max(0, progress), 0.75)
    readonly property real bodyLeft: sourceLeft + closedCorner + (targetRect.x - sourceLeft - closedCorner) * spread
    readonly property real bodyRight: sourceRight - closedCorner + (targetRect.x + targetRect.width - sourceRight + closedCorner) * spread
    readonly property real bodyHeight: targetRect.height * progress
    readonly property real bodyTop: panelHeight + (targetRect.y - panelHeight) * progress
    readonly property real bodyBottom: bodyTop + bodyHeight
    readonly property real joinRadius: closedCorner + (12 - closedCorner) * progress
    // At the screen edge, the outer corner and the attachment share the space
    // available. This keeps their curves tangent instead of folding over.
    readonly property real rightCorner: Math.min(24 * spread, bodyHeight / 2, Math.max(0, bodyRight - sourceRight))
    readonly property real leftCorner: Math.min(24 * spread, bodyHeight / 2, Math.max(0, sourceLeft - bodyLeft))
    readonly property real bottomCorner: Math.min(24 * spread, bodyHeight / 2, (bodyRight - bodyLeft) / 2)
    readonly property real rightJoin: Math.min(sourceRight - closedCorner + (closedCorner + 12) * progress, bodyRight - rightCorner)
    readonly property real leftJoin: Math.max(sourceLeft + closedCorner - (closedCorner + 12) * progress, bodyLeft + leftCorner)
    antialiasing: true
    ShapePath {
        strokeWidth: 0; fillColor: root.color
        startX: root.originX; startY: 0
        PathLine { x: root.originX + root.originWidth; y: 0 }
        PathCubic { x: root.sourceRight; y: root.shoulderHeight; control1X: root.originX + root.originWidth - root.shoulder * 0.35; control1Y: 0; control2X: root.sourceRight; control2Y: root.shoulderHeight / 2 }
        PathLine { x: root.sourceRight; y: root.bodyTop - root.joinRadius }
        PathCubic { x: root.rightJoin; y: root.bodyTop; control1X: root.sourceRight; control1Y: root.bodyTop - root.joinRadius / 3; control2X: (2 * root.sourceRight + root.rightJoin) / 3; control2Y: root.bodyTop }
        PathLine { x: root.bodyRight - root.rightCorner; y: root.bodyTop }
        PathQuad { x: root.bodyRight; y: root.bodyTop + root.rightCorner; controlX: root.bodyRight; controlY: root.bodyTop }
        PathLine { x: root.bodyRight; y: root.bodyBottom - root.bottomCorner }
        PathQuad { x: root.bodyRight - root.bottomCorner; y: root.bodyBottom; controlX: root.bodyRight; controlY: root.bodyBottom }
        PathLine { x: root.bodyLeft + root.bottomCorner; y: root.bodyBottom }
        PathQuad { x: root.bodyLeft; y: root.bodyBottom - root.bottomCorner; controlX: root.bodyLeft; controlY: root.bodyBottom }
        PathLine { x: root.bodyLeft; y: root.bodyTop + root.leftCorner }
        PathQuad { x: root.bodyLeft + root.leftCorner; y: root.bodyTop; controlX: root.bodyLeft; controlY: root.bodyTop }
        PathLine { x: root.leftJoin; y: root.bodyTop }
        PathCubic { x: root.sourceLeft; y: root.bodyTop - root.joinRadius; control1X: (2 * root.sourceLeft + root.leftJoin) / 3; control1Y: root.bodyTop; control2X: root.sourceLeft; control2Y: root.bodyTop - root.joinRadius / 3 }
        PathLine { x: root.sourceLeft; y: root.shoulderHeight }
        PathCubic { x: root.originX; y: 0; control1X: root.sourceLeft; control1Y: root.shoulderHeight / 2; control2X: root.originX + root.shoulder * 0.35; control2Y: 0 }
    }
}
