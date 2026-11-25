import QtQuick
import QtQuick.Shapes

// The compact pill's lower edge and ends stay still until a kick: then the
// glass pops outward and springs back with a short liquid wobble. Stronger
// kicks pop farther, and each side swells with its own channel's bass. The
// liquid is one band from just inside the pill's edge to the crest, in the
// same glass, so the edge itself moves.
Shape {
    id: root
    required property var theme
    required property var levels
    required property real pillWidth
    required property real pillHeight
    property bool active: false
    readonly property real reach: 20
    property real strength: active ? 1 : 0
    Behavior on strength { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    // Damped springs per side: displacement and velocity.
    property real leftSwell: 0
    property real rightSwell: 0
    property real leftVelocity: 0
    property real rightVelocity: 0
    property real peak: 0
    property var outline: []
    readonly property bool animating: peak > 0.05 || Math.abs(leftVelocity) + Math.abs(rightVelocity) > 0.5

    x: -reach; y: -reach
    width: pillWidth + 2 * reach
    height: pillHeight + 2 * reach
    visible: animating
    enabled: false
    preferredRendererType: Shape.CurveRenderer

    onAnimatingChanged: { if (!animating) outline = []; }
    Connections {
        target: root.levels
        function onBeatsChanged() {
            if (!root.active) return;
            const kick = 280 * root.levels.beatStrength;
            const bass = values => Math.max(values[0] ?? 0, values[1] ?? 0);
            const l = bass(root.levels.left), r = bass(root.levels.right), loudest = Math.max(l, r, 0.01);
            root.leftVelocity += kick * (0.35 + 0.65 * l / loudest);
            root.rightVelocity += kick * (0.35 + 0.65 * r / loudest);
        }
    }

    // Arc-length point and outward normal on the pill outline, clockwise from
    // the top-left end of the straight top edge.
    function stadium(s) {
        const r = pillHeight / 2, straight = Math.max(0, pillWidth - pillHeight);
        const cx = reach + pillWidth / 2, cy = reach + r;
        if (s < straight) return {x: cx - straight / 2 + s, y: cy - r, nx: 0, ny: -1};
        s -= straight;
        if (s < Math.PI * r) { const a = -Math.PI / 2 + s / r; return {x: cx + straight / 2 + r * Math.cos(a), y: cy + r * Math.sin(a), nx: Math.cos(a), ny: Math.sin(a)}; }
        s -= Math.PI * r;
        if (s < straight) return {x: cx + straight / 2 - s, y: cy + r, nx: 0, ny: 1};
        s -= straight;
        const a = Math.PI / 2 + Math.min(s / r, Math.PI); return {x: cx - straight / 2 + r * Math.cos(a), y: cy + r * Math.sin(a), nx: Math.cos(a), ny: Math.sin(a)};
    }
    function step(dt) {
        dt = Math.min(0.05, Math.max(0.001, dt));
        const r = pillHeight / 2, straight = Math.max(0, pillWidth - pillHeight);
        const perimeter = 2 * straight + 2 * Math.PI * r;
        // The surface runs from the top of the right end, around the bottom, to
        // the top of the left end; the top edge stays flat.
        const samples = [];
        for (let s = straight; s <= perimeter; s += 1) {
            const p = stadium(Math.min(s, perimeter - 0.001));
            if (p.ny > -0.8) samples.push({s: s, p: p});
        }
        // About two wobbles per second, settling within half a second.
        const stiffness = 160, damping = 12;
        leftVelocity += (-stiffness * leftSwell - damping * leftVelocity) * dt;
        rightVelocity += (-stiffness * rightSwell - damping * rightVelocity) * dt;
        leftSwell += leftVelocity * dt;
        rightSwell += rightVelocity * dt;
        // Settle exactly so the frame loop can stop.
        if (Math.abs(leftVelocity) + Math.abs(rightVelocity) < 0.5 && Math.abs(leftSwell) + Math.abs(rightSwell) < 0.05)
            leftSwell = rightSwell = leftVelocity = rightVelocity = 0;
        const cx = reach + pillWidth / 2;

        const outer = [], inner = [];
        const last = samples.length - 1;
        let highest = 0;
        samples.forEach((sample, index) => {
            const {s, p} = sample;
            const weight = Math.max(0, Math.min(1, (p.ny + 0.75) / 0.45));
            // Crossfade the sides across the width; fixed soft lobes keep the
            // swell from looking like a plain balloon.
            const share = Math.max(0, Math.min(1, 0.5 + (p.x - cx) / pillWidth * 1.2));
            const lobes = 0.7 + 0.3 * Math.pow(Math.sin(s * 0.06 + 0.6), 2);
            const d = Math.max(0, weight * strength * lobes * (leftSwell + (rightSwell - leftSwell) * share));
            highest = Math.max(highest, d);
            // Cover the pill's rim, tapering to nothing where the surface ends.
            const inset = 1.75 * Math.min(1, Math.min(index, last - index) / 8);
            outer.push(Qt.point(p.x + p.nx * d, p.y + p.ny * d));
            inner.push(Qt.point(p.x - p.nx * inset, p.y - p.ny * inset));
        });
        peak = highest;
        outline = outer.concat(inner.reverse());
    }

    FrameAnimation {
        running: root.animating
        onTriggered: root.step(frameTime)
    }
    ShapePath {
        strokeWidth: -1
        fillGradient: LinearGradient {
            x1: 0; y1: root.reach; x2: 0; y2: root.reach + root.pillHeight
            GradientStop { position: root.theme.compactGlassStops[0][0]; color: root.theme.compactGlassStops[0][1] }
            GradientStop { position: root.theme.compactGlassStops[1][0]; color: root.theme.compactGlassStops[1][1] }
            GradientStop { position: root.theme.compactGlassStops[2][0]; color: root.theme.compactGlassStops[2][1] }
        }
        PathPolyline { path: root.outline }
    }
}
