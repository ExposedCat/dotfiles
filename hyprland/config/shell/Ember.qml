import QtQuick

// One shape: pull out into a bead, leap, then unfold into the destination.
// Dock beneath the destination's labels only after the landing has settled.
Item {
    id: root
    enabled: false
    property bool ready: false
    property bool hasPosition: false
    property Item target: null
    property bool active: false
    property Item dock: null
    property rect origin: Qt.rect(0, 0, 10, 10)
    property rect destination: origin
    property real originRadius: 5
    property real originOpacity: 1
    property real travel: 1
    property real blink: 1
    readonly property real beadSize: 10
    property real takeoffEnd: 0.22
    property bool redirecting: false
    property real interruptedAt: -1000
    readonly property real landingStart: 0.72
    readonly property bool moving: flight.running
    readonly property string phase: !moving ? "rest" : travel < takeoffEnd ? "takeoff" : travel < landingStart ? "jump" : "landing"
    function mix(a, b, t) { return a + (b - a) * t; }
    function outCubic(t) { return 1 - Math.pow(1 - t, 3); }
    readonly property var pose: {
        const t = travel;
        const start = Qt.point(origin.x + origin.width / 2, origin.y + origin.height / 2);
        const end = Qt.point(destination.x + destination.width / 2, destination.y + destination.height / 2);
        let center = start, w = beadSize, h = beadSize, radius = beadSize / 2, alpha = 1;
        if (t < takeoffEnd) {
            const u = outCubic(t / takeoffEnd);
            w = mix(origin.width, beadSize, u); h = mix(origin.height, beadSize, u);
            radius = mix(originRadius, beadSize / 2, u); alpha = mix(originOpacity, 1, u);
        } else if (t < landingStart) {
            const u = (t - takeoffEnd) / (landingStart - takeoffEnd);
            const progress = redirecting ? outCubic(u) : u * u * (3 - 2 * u);
            const distance = Math.hypot(end.x - start.x, end.y - start.y);
            // Keep the hop inside the pill, including its shallow header.
            const lift = Math.min(30, Math.max(12, distance * 0.1), Math.max(0, Math.min(start.y, end.y) - beadSize / 2 - 2));
            center = Qt.point(mix(start.x, end.x, progress), mix(start.y, end.y, progress) - 4 * u * (1 - u) * lift);
            const stretch = Math.sin(Math.PI * u);
            w = beadSize * (1 + 0.16 * stretch); h = beadSize * (1 - 0.10 * stretch);
            radius = Math.min(w, h) / 2;
        } else {
            const u = Math.min(1, (t - landingStart) / (1 - landingStart));
            // A small landing overshoot gives the bead weight without wobbling text.
            const v = u - 1, spring = 1 + 2.2 * v * v * v + 1.2 * v * v;
            center = end;
            w = mix(beadSize, destination.width, spring); h = mix(beadSize, destination.height, spring);
            radius = mix(beadSize / 2, target ? target.shapeRadius : originRadius, spring);
            alpha = mix(1, target ? target.shapeOpacity : originOpacity, outCubic(u));
        }
        return {rect: Qt.rect(center.x - w / 2, center.y - h / 2, Math.max(1, w), Math.max(1, h)), radius: Math.max(0, radius), alpha: alpha};
    }
    readonly property rect geometry: pose.rect
    function locate() {
        if (!target) return;
        const p = target.mapToItem(root, 0, 0);
        destination = Qt.rect(p.x, p.y, target.width, target.height);
    }
    function depart() {
        const p = shape.mapToItem(root, 0, 0);
        let bounds = Qt.rect(p.x, p.y, shape.width, shape.height);
        let radius = shape.radius, alpha = shape.opacity;
        const wasMoving = flight.running;
        const continuing = wasMoving || Date.now() - interruptedAt < 120;
        flight.stop();
        dock = null;
        if (!target) {
            if (wasMoving) interruptedAt = Date.now();
            origin = bounds; destination = bounds; originRadius = radius; originOpacity = alpha;
            travel = 1; return;
        }
        locate();
        if (!hasPosition) {
            bounds = Qt.rect(destination.x + (destination.width - beadSize) / 2, destination.y + (destination.height - beadSize) / 2, beadSize, beadSize);
            radius = beadSize / 2; alpha = 1; hasPosition = true;
        }
        origin = bounds; originRadius = radius; originOpacity = alpha;
        redirecting = continuing;
        takeoffEnd = continuing ? 0.06 : 0.22;
        travel = continuing && bounds.width <= 12 && bounds.height <= 12 ? takeoffEnd : 0;
        flight.duration = continuing ? 280 : 430;
        flight.restart();
    }
    Component.onCompleted: { ready = true; if (target) depart(); }
    onTargetChanged: { if (ready) depart(); }
    Connections {
        target: root.target
        function onMotionKeyChanged() { if (root.ready && root.dock === root.target) root.depart(); }
    }
    Timer { interval: 16; repeat: true; running: flight.running; onTriggered: root.locate() }
    NumberAnimation {
        id: flight; target: root; property: "travel"; to: 1; duration: 480; easing.type: Easing.Linear
        onFinished: { root.locate(); root.dock = root.target; }
    }
    SequentialAnimation on blink {
        running: root.active && !!root.dock && root.dock.caret; loops: Animation.Infinite
        NumberAnimation { to: 0.25; duration: 550 }
        NumberAnimation { to: 1; duration: 550 }
    }
    Rectangle {
        id: shape
        enabled: false
        objectName: "emberShape"
        parent: root.dock || root
        x: root.dock ? 0 : root.geometry.x
        y: root.dock ? 0 : root.geometry.y
        width: root.dock ? root.dock.width : root.geometry.width
        height: root.dock ? root.dock.height : root.geometry.height
        radius: root.dock ? root.dock.shapeRadius : root.pose.radius
        color: "#cc7855"
        opacity: root.active && root.target ? (root.dock ? root.dock.shapeOpacity * (root.dock.caret ? root.blink : 1) : root.pose.alpha) : 0
        Behavior on opacity { enabled: !flight.running; NumberAnimation { duration: 90 } }
        visible: root.active && opacity > 0
    }
}
