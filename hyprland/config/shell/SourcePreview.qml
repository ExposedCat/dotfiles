import QtQuick
import Quickshell.Widgets

ClippingRectangle {
    id: root
    required property var sourceData
    required property var theme
    property bool fixture: false
    readonly property bool hasPreview: fixture || !!(capture.item && capture.item.hasContent)
    color: "#111111"
    radius: 10
    clip: true
    Rectangle {
        anchors.centerIn: parent
        width: 34; height: 24; radius: 4
        color: "transparent"; border.width: 1; border.color: "#444444"
        visible: !root.hasPreview
        Rectangle { x: 1; y: 6; width: parent.width - 2; height: 1; color: "#444444" }
        Accessible.name: "Preview unavailable"
    }
    Loader {
        id: capture
        anchors.fill: parent
        source: root.sourceData.kind === "workspace" || (root.fixture && root.sourceData.tiles) ? "WorkspacePreview.qml" : root.fixture ? "SamplePreview.qml" : "LivePreview.qml"
        onLoaded: {
            item.sourceData = Qt.binding(() => root.sourceData);
            item.theme = root.theme;
            item.fixture = root.fixture;
        }
    }
}
