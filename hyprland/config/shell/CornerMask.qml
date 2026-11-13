import QtQuick
import QtQuick.Shapes

// The black area outside a circular top-left screen corner.
Shape {
    id: root
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeWidth: 0
        fillColor: "#000000"
        startX: 0; startY: 0
        PathLine { x: root.width; y: 0 }
        PathArc { x: 0; y: root.height; radiusX: root.width; radiusY: root.height; direction: PathArc.Counterclockwise }
        PathLine { x: 0; y: 0 }
    }
}
