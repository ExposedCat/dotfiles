import QtQuick

Rectangle {
    id: root
    required property var theme
    property string hint: "Dismiss notification"
    property bool grouped: false
    property real progress: 0
    property bool armed: false
    property bool completed: false
    signal clicked()
    signal groupDismissed()
    implicitWidth: 30; implicitHeight: 30
    radius: 8; color: "transparent"
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: hint
    Accessible.description: grouped ? "Hold to dismiss the entire notification group" : ""
    Accessible.onPressAction: clicked()

    function beginHold() {
        armed = true; completed = false;
        progress = 0;
        if (grouped) fill.restart();
    }
    function cancelHold() {
        fill.stop(); progress = 0; armed = false;
    }
    function releaseHold() {
        const single = armed && !completed;
        cancelHold();
        if (single) clicked();
    }
    onEnabledChanged: { if (!enabled) cancelHold(); }
    onVisibleChanged: { if (!visible) cancelHold(); }
    onActiveFocusChanged: { if (!activeFocus && !pointer.pressed) cancelHold(); }
    onGroupedChanged: cancelHold()
    Keys.onPressed: event => {
        if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return;
        event.accepted = true;
        if (!event.isAutoRepeat) beginHold();
    }
    Keys.onReleased: event => {
        if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return;
        event.accepted = true;
        if (!event.isAutoRepeat) releaseHold();
    }
    EmberControl { control: root; anchors.fill: parent; shapeRadius: root.radius }
    NumberAnimation {
        id: fill
        target: root; property: "progress"; from: 0; to: 1; duration: 520
        onFinished: {
            if (!root.armed) return;
            root.completed = true;
            root.groupDismissed();
        }
    }
    Canvas {
        id: circle
        anchors.fill: parent
        visible: root.progress > 0
        Connections { target: root; function onProgressChanged() { circle.requestPaint(); } }
        onPaint: {
            const ctx = getContext("2d"), cx = width / 2, cy = height / 2, r = 13;
            const start = -Math.PI / 2, end = start + Math.PI * 2 * root.progress;
            ctx.clearRect(0, 0, width, height);
            ctx.beginPath(); ctx.moveTo(cx, cy); ctx.arc(cx, cy, r, start, end); ctx.closePath();
            ctx.fillStyle = Qt.alpha(root.theme.red, 0.25); ctx.fill();
            ctx.beginPath(); ctx.arc(cx, cy, r, start, end);
            ctx.strokeStyle = root.theme.red; ctx.lineWidth = 2; ctx.stroke();
        }
    }
    ShellIcon { anchors.centerIn: parent; name: "x"; width: 21; height: 21 }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onPressed: root.beginHold()
        onReleased: root.releaseHold()
        onCanceled: root.cancelHold()
        onExited: root.cancelHold()
    }
}
