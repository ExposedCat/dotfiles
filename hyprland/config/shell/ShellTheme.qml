import QtQuick

QtObject {
    readonly property int panelHeight: 30
    readonly property int panelGap: 8
    readonly property int panelWing: 12
    readonly property int notificationWidth: 560
    readonly property int screenCornerRadius: 16
    readonly property string fontFamily: "Adwaita Sans"
    readonly property int fontWeight: Font.Normal
    readonly property int bodySize: 18
    readonly property int smallSize: bodySize
    property color background: "#000000"
    property color surface: "#191919"
    property color hover: "#333333"
    property color border: "#333333"
    property color text: "#f5f5f5"
    property color secondary: "#cccccc"
    property color accent: "#89b4fa"
    property color green: "#a6e3a1"
    property color red: "#f38ba8"
    property color amber: "#f9e2af"
}
