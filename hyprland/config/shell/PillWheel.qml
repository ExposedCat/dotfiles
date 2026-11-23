import QtQuick

WheelHandler {
    id: root
    required property Flickable flickable
    property int duration: 0
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    readonly property real scrollExtent: Math.max(0, flickable.contentHeight
        + flickable.topMargin + flickable.bottomMargin - flickable.height)
    enabled: scrollExtent > 0
    onEnabledChanged: { if (!enabled) glide.stop(); }

    function stop() { glide.stop(); }
    function bounded(position) {
        const top = flickable.originY - flickable.topMargin;
        return Math.max(top, Math.min(top + scrollExtent, position));
    }

    readonly property NumberAnimation glide: NumberAnimation {
        target: root.flickable
        property: "contentY"
        duration: root.duration
        easing.type: Easing.OutCubic
        onFinished: root.flickable.returnToBounds()
    }
    readonly property Connections drag: Connections {
        target: root.flickable
        function onDraggingChanged() { if (root.flickable.dragging) root.stop(); }
    }
    onWheel: event => {
        const pixels = event.pixelDelta.y;
        const delta = (pixels || event.angleDelta.y / 120 * Qt.styleHints.wheelScrollLines * 20) * 2;
        if (!delta) { event.accepted = false; return; }
        // Pixel events follow the gesture directly. Wheel notches add to the pending destination.
        const startingY = glide.running && !pixels ? glide.to : flickable.contentY;
        glide.stop();
        flickable.cancelFlick();
        const destination = bounded(startingY - delta);
        if (pixels || duration === 0) flickable.contentY = destination;
        else if (destination !== flickable.contentY) {
            glide.from = flickable.contentY;
            glide.to = destination;
            glide.start();
        }
        event.accepted = true;
    }
}
