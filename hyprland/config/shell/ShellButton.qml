import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property var theme
    property string icon: ""
    property string text: ""
    property string hint: ""
    // Hints name icon buttons for accessibility; the shell never shows tooltips.
    property bool selected: false
    property bool danger: false
    property bool indicator: false
    property var emberShell: null
    property alias emberSlot: emberSlot
    signal clicked(int button)
    signal scrolled(real delta)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: text || hint
    Accessible.onPressAction: clicked(Qt.LeftButton)
    Keys.onReturnPressed: clicked(Qt.LeftButton)
    Keys.onSpacePressed: clicked(Qt.LeftButton)
    readonly property real implicitContentWidth: content.implicitWidth
    property int iconSize: 21
    property int textSize: theme.bodySize
    property string textFamily: theme.fontFamily
    property bool pending: false
    property bool elideText: false
    implicitWidth: content.implicitWidth + 22
    implicitHeight: 36
    radius: 8
    readonly property bool hovered: buttonHover.hovered
    color: emberSlot.occupied ? "transparent" : selected ? theme.surface : "transparent"
    border.width: activeFocus ? 1 : 0
    border.color: danger ? theme.red : theme.accent
    opacity: enabled || pending ? 1 : 0.45
    EmberSlot { id: emberSlot; shell: root.emberShell; anchors.fill: parent; shapeRadius: root.radius; shapeOpacity: 0.42 }
    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 7
        ShellIcon { name: root.icon; Layout.preferredWidth: root.iconSize; Layout.preferredHeight: root.iconSize; visible: root.icon.length > 0 && !root.pending }
        Spinner { visible: root.pending; running: visible; Layout.preferredWidth: root.iconSize; Layout.preferredHeight: root.iconSize }
        Text { font.family: root.textFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.textSize; Layout.maximumWidth: root.elideText ? Math.max(0, root.width - 22 - (root.icon.length > 0 || root.pending ? root.iconSize + 7 : 0) - (root.indicator ? 13 : 0)) : Infinity; elide: Text.ElideRight; visible: root.text.length > 0; text: root.text; textFormat: Text.PlainText; color: root.danger ? root.theme.red : root.selected ? root.theme.accent : root.theme.text }
        Rectangle { visible: root.indicator; Layout.preferredWidth: 6; Layout.preferredHeight: 6; radius: 3; color: root.theme.accent }
    }
    HoverHandler { id: buttonHover }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: event => root.clicked(event.button)
        onWheel: event => root.scrolled(event.angleDelta.y)
    }



}
