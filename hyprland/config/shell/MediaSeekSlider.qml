import QtQuick

PillSlider {
    id: root
    objectName: "mediaSeek"
    property real pendingPosition: NaN
    property string trackKey: ""
    property string pressedTrack: ""
    signal seekRequested(real position)
    Accessible.name: "Playback position"
    // Drag locally and send a single seek to the player when released.
    onMoved: {
        if (pressed) pendingPosition = value;
        else seekRequested(value);
    }
    onPressedChanged: {
        if (pressed) {
            pressedTrack = trackKey;
        } else if (Number.isFinite(pendingPosition)) {
            const position = pendingPosition;
            pendingPosition = NaN;
            if (pressedTrack === trackKey) seekRequested(position);
        }
    }
}
