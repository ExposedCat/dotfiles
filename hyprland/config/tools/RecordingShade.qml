import QtQuick
import Quickshell
import Quickshell.Wayland
import "CaptureGeometry.js" as Geometry

PanelWindow {
    id: shade
    required property var display
    required property var selection
    screen: Quickshell.screens.find(s => s.name === display.name) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Empty input region: applications remain clickable across both displays.
    mask: Region {}
    WlrLayershell.namespace: "dotfiles-record-shade"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    readonly property var localSelection: Geometry.local(selection, display)
    readonly property bool target: localSelection.width > 0 && localSelection.height > 0
    readonly property color dim: "#99000000"

    Rectangle { width: shade.width; height: shade.target ? localSelection.y : shade.height; color: shade.dim }
    Rectangle { visible: shade.target; x: 0; y: localSelection.y; width: localSelection.x; height: localSelection.height; color: shade.dim }
    Rectangle { visible: shade.target; x: localSelection.x + localSelection.width; y: localSelection.y; width: Math.max(0, shade.width - x); height: localSelection.height; color: shade.dim }
    Rectangle { visible: shade.target; x: 0; y: localSelection.y + localSelection.height; width: shade.width; height: Math.max(0, shade.height - y); color: shade.dim }

    // These edges are strictly outside the encoded global rectangle.
    Rectangle { x: selection.x - display.x - 2; y: selection.y - display.y - 2; width: selection.width + 4; height: 2; color: "#cc7855" }
    Rectangle { x: selection.x - display.x - 2; y: selection.y - display.y + selection.height; width: selection.width + 4; height: 2; color: "#cc7855" }
    Rectangle { x: selection.x - display.x - 2; y: selection.y - display.y; width: 2; height: selection.height; color: "#cc7855" }
    Rectangle { x: selection.x - display.x + selection.width; y: selection.y - display.y; width: 2; height: selection.height; color: "#cc7855" }
}
