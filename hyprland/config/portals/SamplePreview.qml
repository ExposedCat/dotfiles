import QtQuick

// Only loaded for explicit fixture previews. Production uses live screencopy.
Rectangle {
    id: root
    property var sourceData: ({})
    property var theme
    property bool fixture: true
    readonly property string flavor: sourceData.flavor || "code"
    color: flavor === "browser" ? "#202124" : "#15181d"
    Rectangle {
        id: bar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: Math.max(10, parent.height * 0.1)
        color: "#303239"
        Row {
            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter } spacing: 3
            Repeater { model: ["#d77478", "#d8bb76", "#87b38b"]; Rectangle { required property var modelData; width: 3; height: 3; radius: 1.5; color: modelData } }
        }
    }
    Item {
        anchors { top: bar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        Rectangle { visible: root.flavor !== "terminal"; width: parent.width * 0.19; height: parent.height; color: "#1d2026" }
        Repeater {
            model: root.flavor === "browser" ? 0 : 8
            Rectangle {
                required property int index
                x: root.flavor === "terminal" ? 10 : parent.width * 0.25 + (index % 3 === 1 ? 6 : 0)
                y: 9 + index * (parent.height - 16) / 9
                width: parent.width * [0.43, 0.54, 0.24, 0.48, 0.32][index % 5]
                height: Math.max(1, parent.height * 0.02); radius: 1
                color: root.flavor === "terminal" ? (index % 3 ? "#a4b4aa" : "#87b797") : ["#c28fb0", "#91adc3", "#b8bd97"][index % 3]
                opacity: 0.85
            }
        }
        Rectangle {
            visible: root.flavor === "browser"
            x: parent.width * 0.25; y: parent.height * 0.1
            width: parent.width * 0.68; height: parent.height * 0.78; radius: 3
            color: "#e2e1dd"
            Rectangle { x: parent.width * 0.08; y: parent.height * 0.13; width: parent.width * 0.49; height: parent.height * 0.06; color: "#6f7881"; radius: 1 }
            Rectangle { x: parent.width * 0.08; y: parent.height * 0.29; width: parent.width * 0.84; height: parent.height * 0.45; color: "#babfc2"; radius: 2 }
            Rectangle { x: parent.width * 0.08; y: parent.height * 0.84; width: parent.width * 0.72; height: parent.height * 0.03; color: "#858c92" }
        }
    }
}
