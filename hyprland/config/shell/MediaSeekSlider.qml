import QtQuick

PillSlider {
    id: root
    objectName: "mediaSeek"
    property bool playing: false
    property bool animating: false
    property real phase: 0
    property real amplitude: playing ? 5 : 2.5
    Behavior on amplitude { NumberAnimation { duration: 220 } }
    NumberAnimation on phase {
        from: 0; to: Math.PI * 2; duration: 2600; loops: Animation.Infinite
        running: root.playing && root.animating && root.visible
    }
    background: Canvas {
        id: wave
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        width: root.availableWidth; height: 22
        readonly property real progress: root.visualPosition
        readonly property real phase: root.phase
        readonly property real amplitude: root.amplitude
        readonly property color ink: root.theme.text
        onWidthChanged: requestPaint()
        onProgressChanged: requestPaint()
        onPhaseChanged: requestPaint()
        onAmplitudeChanged: requestPaint()
        onInkChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            // Land on the seek handle and soften both ends of the ribbon.
            const center = root.handle.x + root.handle.width / 2 - x;
            function yAt(px) {
                const edges = Math.min(1, px / 12, (width - px) / 12);
                const landing = Math.min(1, Math.abs(px - center) / 14);
                return height / 2 + amplitude * edges * landing
                    * (0.8 * Math.sin(px * Math.PI * 2 / 38 - phase)
                       + 0.2 * Math.sin(px * Math.PI * 2 / 76 + phase));
            }
            function draw() {
                ctx.beginPath();
                for (let px = 0; px < width; px += 1.5) {
                    if (px === 0) ctx.moveTo(px, yAt(px));
                    else ctx.lineTo(px, yAt(px));
                }
                ctx.lineTo(width, height / 2);
                ctx.stroke();
            }
            ctx.lineWidth = 2.5; ctx.lineCap = "round"; ctx.lineJoin = "round";
            ctx.strokeStyle = Qt.alpha(ink, 0.22); draw();
            ctx.save(); ctx.beginPath(); ctx.rect(0, 0, center, height); ctx.clip();
            ctx.strokeStyle = Qt.alpha(ink, 0.9); draw(); ctx.restore();
        }
    }
}
