import QtQuick
import QtQuick.Effects

Item {
    id: root
    required property var theme
    required property real compactHeight
    required property real compactRadius
    required property real frameRadius
    property var panelGradient: null
    property real overviewBlend: 0
    property bool resizing: false
    property real targetArea: 0
    // Feedback changes the width and content, but uses the same short surface.
    readonly property bool compact: !panelGradient && height <= compactHeight
    readonly property real expandedOpacity: panelGradient ? 1 : overviewBlend
    // Rasterize large gradients at half resolution during the resize only.
    readonly property real resolutionScale: resizing && Math.max(width * height, targetArea) > 640000 ? 0.5 : 1
    enabled: false

    PillBackground {
        anchors.fill: parent
        theme: root.theme
        radius: root.compactRadius + Math.round(11 * root.overviewBlend)
        visible: !root.panelGradient && !root.compact
    }

    RectangularShadow {
        anchors.fill: parent
        radius: root.frameRadius
        blur: 45
        offset: Qt.vector2d(0, 20)
        color: root.theme.overviewShadow
        opacity: root.expandedOpacity
        visible: opacity > 0
    }

    PillOverviewSurface {
        width: root.width * resolutionScale
        height: root.height * resolutionScale
        resolutionScale: root.resolutionScale
        smooth: true
        transform: Scale {
            xScale: 1 / root.resolutionScale
            yScale: xScale
        }
        theme: root.theme
        radius: (root.compact ? root.compactRadius : root.frameRadius) * resolutionScale
        glassStops: root.compact ? root.theme.compactGlassStops : null
        panelGradient: root.panelGradient
        overviewBlend: root.overviewBlend
        opacity: root.compact ? 1 : root.expandedOpacity
        visible: opacity > 0
    }
}
