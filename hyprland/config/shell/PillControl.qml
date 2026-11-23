import QtQuick

ShellButton {
    property int preferredIconSize: theme.overviewControlIconSize
    readonly property bool highlighted: hovered || emberSlot.occupied

    implicitWidth: theme.overviewControlSize
    implicitHeight: implicitWidth
    radius: theme.overviewControlRadius
    iconSize: Math.min(preferredIconSize, Math.max(0, width - 12))
    iconTint: selected ? theme.overviewAccent : danger ? theme.overviewPowerInk : theme.overviewInk
    color: selected ? Qt.alpha(theme.overviewAccent, 0.24)
        : highlighted ? theme.overviewButtonHover : danger ? theme.overviewPowerFill : theme.overviewButton
}
