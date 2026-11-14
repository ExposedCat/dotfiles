import QtQuick

// Keep mouse wheels and pixel-based touchpad scrolling at twice the normal step.
WheelHandler {
    id: root
    required property Flickable flickable
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    enabled: flickable.contentHeight > flickable.height
    onWheel: event => {
        const delta = (event.pixelDelta.y || event.angleDelta.y / 120 * Qt.styleHints.wheelScrollLines * 20) * 2;
        if (!delta) { event.accepted = false; return; }
        const top = flickable.originY;
        const bottom = Math.max(top, top + flickable.contentHeight - flickable.height);
        flickable.cancelFlick();
        flickable.contentY = Math.max(top, Math.min(bottom, flickable.contentY - delta));
        event.accepted = true;
    }
}
