import QtQuick
import QtQuick.Shapes

// Ferrofluid on the compact pill: its lower edge and ends stay still until a
// kick, then the glass swells a little and a row of rounded spikes shoots out
// of it, like the liquid on a magnet speaker, before sinking back. Stronger
// kicks raise taller spikes, each side follows its own channel's bass, and
// every spike gets its own height and spring so the row looks alive. The
// liquid is one band from just inside the pill's edge to the tips, in the
// same glass, so the edge itself moves.
Shape {
    id: root
    required property var theme
    required property var levels
    required property real pillWidth
    required property real pillHeight
    property bool active: false
    readonly property real reach: 20
    // Spike pitch along the edge, flank falloff, and tip rounding, in pixels.
    readonly property real spikeSpacing: 18
    readonly property real spikeWidth: 3
    readonly property real spikeTip: 3
    property real strength: active ? 1 : 0
    Behavior on strength { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    // Damped springs per side for the body swell: displacement and velocity.
    property real leftSwell: 0
    property real rightSwell: 0
    property real leftVelocity: 0
    property real rightVelocity: 0
    // Per spike: arc position, x, stiffness, height, and velocity.
    property var spikes: []
    property var surface: null
    property real motion: 0
    property real peak: 0
    property var outline: []
    readonly property bool animating: peak > 0.05 || motion > 0.5

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
            root.layout();
            const kick = 280 * root.levels.beatStrength;
            const bass = values => Math.max(values[0] ?? 0, values[1] ?? 0);
            const l = bass(root.levels.left), r = bass(root.levels.right), loudest = Math.max(l, r, 0.01);
            const leftKick = kick * (0.35 + 0.65 * l / loudest), rightKick = kick * (0.35 + 0.65 * r / loudest);
            root.leftVelocity += leftKick;
            root.rightVelocity += rightKick;
            const beat = root.levels.beats;
            root.spikes.forEach((spike, index) => {
                const share = root.sideShare(spike.x);
                spike.velocity += (leftKick + (rightKick - leftKick) * share) * (0.55 + 0.45 * root.noise(index, beat));
            });
            root.motion = Math.abs(root.leftVelocity) + Math.abs(root.rightVelocity);
        }
    }

    // Deterministic 0..1 noise, so fixture sessions render the same spikes.
    function noise(index, beat) {
        const v = Math.sin(index * 12.9898 + beat * 78.233) * 43758.5453;
        return v - Math.floor(v);
    }
    // Crossfade from the left channel to the right across the width.
    function sideShare(x) {
        return Math.max(0, Math.min(1, 0.5 + (x - reach - pillWidth / 2) / pillWidth * 1.2));
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
    // The surface runs from the top of the right end, around the bottom, to
    // the top of the left end; the top edge stays flat. Spikes sit evenly
    // along it and keep their motion when the pill resizes.
    function layout() {
        if (surface && surface.width === pillWidth && surface.height === pillHeight) return;
        const r = pillHeight / 2, straight = Math.max(0, pillWidth - pillHeight);
        const perimeter = 2 * straight + 2 * Math.PI * r;
        const samples = [];
        for (let s = straight; s <= perimeter; s += 1) {
            const p = stadium(Math.min(s, perimeter - 0.001));
            if (p.ny > -0.8) samples.push({s: s, p: p, weight: Math.max(0, Math.min(1, (p.ny + 0.75) / 0.45))});
        }
        const first = samples[0].s, span = samples[samples.length - 1].s - first;
        const count = Math.max(1, Math.round(span / spikeSpacing));
        const next = [];
        for (let i = 0; i < count; i++) {
            const s = first + span * (i + 0.5) / count;
            const old = spikes[i];
            next.push({s: s, x: stadium(s).x, stiffness: 110 + 60 * noise(i, 0), height: old?.height ?? 0, velocity: old?.velocity ?? 0});
        }
        spikes = next;
        surface = {width: pillWidth, height: pillHeight, samples: samples};
    }
    function step(dt) {
        dt = Math.min(0.05, Math.max(0.001, dt));
        layout();
        // The body wobbles about twice a second and settles within half a
        // second; each spike rises and sinks at its own pace with little
        // bounce, like a thick liquid.
        const stiffness = 160, damping = 12;
        leftVelocity += (-stiffness * leftSwell - damping * leftVelocity) * dt;
        rightVelocity += (-stiffness * rightSwell - damping * rightVelocity) * dt;
        leftSwell += leftVelocity * dt;
        rightSwell += rightVelocity * dt;
        let moving = Math.abs(leftVelocity) + Math.abs(rightVelocity);
        let resting = Math.abs(leftSwell) + Math.abs(rightSwell);
        spikes.forEach(spike => {
            spike.velocity += (-spike.stiffness * spike.height - 14 * spike.velocity) * dt;
            spike.height += spike.velocity * dt;
            moving += Math.abs(spike.velocity);
            resting += Math.abs(spike.height);
        });
        // Settle exactly so the frame loop can stop.
        if (moving < 0.5 && resting < 0.05) {
            leftSwell = rightSwell = leftVelocity = rightVelocity = 0;
            spikes.forEach(spike => { spike.height = spike.velocity = 0; });
            moving = 0;
        }
        motion = moving;

        const samples = surface.samples, last = samples.length - 1;
        const outer = [], inner = [];
        let highest = 0;
        samples.forEach((sample, index) => {
            const {s, p, weight} = sample;
            const body = 0.15 * (leftSwell + (rightSwell - leftSwell) * sideShare(p.x));
            // Cones with concave flanks and a rounded tip, summed so the
            // troughs between neighbours stay smooth.
            let raised = 0;
            spikes.forEach(spike => {
                const u = s - spike.s;
                if (spike.height > 0 && Math.abs(u) < 6 * spikeWidth)
                    raised += spike.height * Math.exp((spikeTip - Math.sqrt(u * u + spikeTip * spikeTip)) / spikeWidth);
            });
            const d = Math.min(reach - 1, Math.max(0, weight * strength * (body + 2 * raised)));
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
