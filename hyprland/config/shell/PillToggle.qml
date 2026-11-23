import QtQuick

ShellButton {
    id: root
    radius: 11
    iconTint: selected ? theme.overviewAccent : theme.overviewInk
    textTint: selected ? theme.selectedGlassInk : theme.overviewInk
    color: hovered && !selected ? theme.overviewButton : "transparent"
    Accessible.checkable: true
    Accessible.checked: selected

    Loader {
        anchors.fill: parent
        z: -1
        active: root.selected
        sourceComponent: PillOverviewSurface {
            theme: root.theme
            radius: root.radius
            glassStops: root.theme.selectedGlassStops
        }
    }
}
