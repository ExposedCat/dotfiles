import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: shade
    required property var display
    required property var selection
    screen: Quickshell.screens.find(s => s.name === display.name) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    // Empty input region: applications remain clickable across both displays.
    mask: Region {}
    WlrLayershell.namespace: "dotfiles-record-shade"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    readonly property bool target: selection.monitor === display.name
    readonly property color dim: "#99000000"

    Rectangle { width: shade.width; height: shade.target ? selection.y : shade.height; color: shade.dim }
    Rectangle { visible: shade.target; x: 0; y: selection.y; width: selection.x; height: selection.height; color: shade.dim }
    Rectangle { visible: shade.target; x: selection.x + selection.width; y: selection.y; width: Math.max(0, shade.width - x); height: selection.height; color: shade.dim }
    Rectangle { visible: shade.target; x: 0; y: selection.y + selection.height; width: shade.width; height: Math.max(0, shade.height - y); color: shade.dim }

    // Draw strictly outside the encoded rectangle so the video stays clean.
    Rectangle { visible: shade.target; x: selection.x - 2; y: selection.y - 2; width: selection.width + 4; height: 2; color: "#f38ba8" }
    Rectangle { visible: shade.target; x: selection.x - 2; y: selection.y + selection.height; width: selection.width + 4; height: 2; color: "#f38ba8" }
    Rectangle { visible: shade.target; x: selection.x - 2; y: selection.y; width: 2; height: selection.height; color: "#f38ba8" }
    Rectangle { visible: shade.target; x: selection.x + selection.width; y: selection.y; width: 2; height: selection.height; color: "#f38ba8" }
}
