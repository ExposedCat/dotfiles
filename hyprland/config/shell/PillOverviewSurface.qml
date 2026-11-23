import QtQuick

Canvas {
    id: root
    required property var theme
    required property real radius
    property var glassStops: null
    property bool highlighted: false
    property bool frameOnly: false
    property real resolutionScale: 1
    readonly property real rimWidth: 1.25 * resolutionScale
    property var panelGradient: null
    property real overviewBlend: 0
    property color rimColor: theme.overviewRim
    property color highlightColor: glassStops ? theme.glassHighlight : theme.overviewHighlight
    property bool highlightInsideRim: true

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onRadiusChanged: requestPaint()
    onGlassStopsChanged: requestPaint()
    onHighlightedChanged: requestPaint()
    onPanelGradientChanged: requestPaint()
    onOverviewBlendChanged: { if (panelGradient) requestPaint(); }
    onRimColorChanged: requestPaint()
    onHighlightColorChanged: requestPaint()
    onHighlightInsideRimChanged: requestPaint()
    onVisibleChanged: { if (visible) requestPaint(); }
    onAvailableChanged: { if (available) requestPaint(); }

    function framePath(ctx, x, y, w, h, r) {
        const corner = Math.max(0, Math.min(r, w / 2, h / 2));
        ctx.beginPath();
        ctx.moveTo(x + corner, y);
        ctx.arcTo(x + w, y, x + w, y + h, corner);
        ctx.arcTo(x + w, y + h, x, y + h, corner);
        ctx.arcTo(x, y + h, x, y, corner);
        ctx.arcTo(x, y, x + w, y, corner);
        ctx.closePath();
    }

    function insetHighlight(ctx, x, y, w, h, r, color) {
        const edge = rimWidth;
        const corner = Math.max(0, Math.min(r, w / 2, h / 2));
        // The translated top edge gives the inset shadow its tapered corners.
        ctx.beginPath();
        ctx.moveTo(x, y + corner);
        ctx.arcTo(x, y, x + w, y, corner);
        ctx.arcTo(x + w, y, x + w, y + h, corner);
        ctx.lineTo(x + w, y + corner + edge);
        ctx.arcTo(x + w, y + edge, x, y + edge, corner);
        ctx.arcTo(x, y + edge, x, y + h, corner);
        ctx.closePath();
        ctx.fillStyle = color;
        ctx.fill();
    }

    function strokeRim(ctx, w, h, r, color) {
        const edge = rimWidth;
        framePath(ctx, edge / 2, edge / 2, w - edge, h - edge, r - edge / 2);
        ctx.strokeStyle = color;
        ctx.lineWidth = edge;
        ctx.stroke();
    }

    function linearGradient(ctx, w, h, degrees) {
        const angle = degrees * Math.PI / 180;
        const dx = Math.sin(angle), dy = -Math.cos(angle);
        const reach = (w * Math.abs(dx) + h * Math.abs(dy)) / 2;
        const x = w / 2, y = h / 2;
        return ctx.createLinearGradient(x - dx * reach, y - dy * reach,
            x + dx * reach, y + dy * reach);
    }

    function paintGlass(ctx, w, h) {
        const wash = linearGradient(ctx, w, h, 132);
        for (const [position, color] of glassStops) wash.addColorStop(position, color);
        ctx.fillStyle = wash;
        ctx.fillRect(0, 0, w, h);
        if (highlighted) strokeRim(ctx, w, h, radius, theme.glassHoverRim);
        else insetHighlight(ctx, 0, 0, w, h, radius, highlightColor);
    }

    function paintGradients(ctx, w, h, layers) {
        for (const layer of layers) {
            ctx.save();
            ctx.globalAlpha *= layer.strength;
            let wash, x = 0, y = 0, rx = 1, ry = 1;
            if (layer.angle !== undefined) {
                wash = linearGradient(ctx, w, layer.referenceHeight === undefined ? h : layer.referenceHeight * resolutionScale, layer.angle);
            } else {
                x = layer.center[0] * w;
                y = layer.center[1] * h;
                // The overview uses a farthest-corner ellipse.
                rx = layer.radii ? layer.radii[0] * w : (w - x) * Math.SQRT2;
                ry = layer.radii ? layer.radii[1] * h : (h - y) * Math.SQRT2;
                ctx.translate(x, y);
                ctx.scale(rx, ry);
                wash = ctx.createRadialGradient(0, 0, 0, 0, 0, 1);
            }
            for (const [position, color] of layer.stops) wash.addColorStop(position, color);
            ctx.fillStyle = wash;
            ctx.fillRect(-x / rx, -y / ry, w / rx, h / ry);
            ctx.restore();
        }
    }

    function paintFrame(ctx, w, h) {
        if (rimColor.a > 0) strokeRim(ctx, w, h, radius, rimColor);
        const inset = highlightInsideRim && rimColor.a > 0 ? rimWidth : 0;
        insetHighlight(ctx, inset, inset, w - 2 * inset, h - 2 * inset, radius - inset, highlightColor);
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        const w = width, h = height;
        if (w < 3 || h < 3) return;
        framePath(ctx, 0, 0, w, h, radius);
        ctx.clip();
        if (frameOnly) paintFrame(ctx, w, h);
        else if (glassStops) paintGlass(ctx, w, h);
        else {
            if (panelGradient) {
                ctx.fillStyle = theme.overviewBase;
                ctx.fillRect(0, 0, w, h);
                paintGradients(ctx, w, h, panelGradient);
            }
            if (!panelGradient || overviewBlend > 0) {
                ctx.globalAlpha = panelGradient ? overviewBlend : 1;
                paintGradients(ctx, w, h, theme.overviewGradient);
                ctx.globalAlpha = 1;
            }
            paintFrame(ctx, w, h);
        }
    }
}
