import QtQuick

Image {
    property string name: ""
    width: 18
    height: 18
    source: name ? Qt.resolvedUrl("icons/" + name + ".svg") : ""
    sourceSize.width: width
    sourceSize.height: height
    fillMode: Image.PreserveAspectFit
}
