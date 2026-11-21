import QtQuick

Canvas {
    id: root
    required property var theme
    required property real radius
    property bool weather: false
    property bool highlighted: false
    readonly property int shadowMargin: weather ? 0 : 72
    readonly property real surfaceWidth: Math.max(0, width - 2 * shadowMargin)
    readonly property real surfaceHeight: Math.max(0, height - 2 * shadowMargin)

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onRadiusChanged: requestPaint()
    onHighlightedChanged: requestPaint()
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
        const edge = 1.25;
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
        const edge = 1.25;
        framePath(ctx, edge / 2, edge / 2, w - edge, h - edge, r - edge / 2);
        ctx.strokeStyle = color;
        ctx.lineWidth = edge;
        ctx.stroke();
    }

    function paintWeather(ctx, w, h) {
        // CSS linear-gradient(132deg) spans the opposing corners.
        const angle = 132 * Math.PI / 180;
        const dx = Math.sin(angle), dy = -Math.cos(angle);
        const reach = (w * dx + h * dy) / 2;
        const x = w / 2, y = h / 2;
        const wash = ctx.createLinearGradient(x - dx * reach, y - dy * reach,
            x + dx * reach, y + dy * reach);
        wash.addColorStop(0, theme.weatherTileTop);
        wash.addColorStop(0.66, theme.weatherTileMiddle);
        wash.addColorStop(1, theme.weatherTileBottom);
        ctx.fillStyle = wash;
        ctx.fillRect(0, 0, w, h);
        if (highlighted) strokeRim(ctx, w, h, radius, theme.weatherHoverRim);
        else insetHighlight(ctx, 0, 0, w, h, radius, theme.weatherHighlight);
    }

    function paintPanel(ctx, w, h) {
        // A farthest-corner ellipse centered at 42% -34%, as in the mockup.
        const x = 0.42 * w, y = -0.34 * h;
        const rx = (w - x) * Math.SQRT2, ry = (h - y) * Math.SQRT2;
        ctx.save();
        ctx.translate(x, y);
        ctx.scale(rx, ry);
        const wash = ctx.createRadialGradient(0, 0, 0, 0, 0, 1);
        wash.addColorStop(0, theme.overviewGlow);
        wash.addColorStop(0.49, theme.overviewMiddle);
        wash.addColorStop(0.87, theme.overviewBase);
        wash.addColorStop(1, theme.overviewBase);
        ctx.fillStyle = wash;
        ctx.fillRect(-x / rx, -y / ry, w / rx, h / ry);
        ctx.restore();
        strokeRim(ctx, w, h, radius, theme.overviewRim);
        insetHighlight(ctx, 1.25, 1.25, w - 2.5, h - 2.5, radius - 1.25, theme.overviewHighlight);
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        const w = surfaceWidth, h = surfaceHeight;
        if (w < 3 || h < 3) return;
        ctx.translate(shadowMargin, shadowMargin);
        if (!weather) {
            ctx.save();
            ctx.shadowColor = theme.overviewShadow;
            ctx.shadowOffsetY = 20;
            ctx.shadowBlur = 45;
            ctx.fillStyle = theme.overviewBase;
            framePath(ctx, 0, 0, w, h, radius);
            ctx.fill();
            ctx.restore();
        }
        framePath(ctx, 0, 0, w, h, radius);
        ctx.clip();
        if (weather) paintWeather(ctx, w, h);
        else paintPanel(ctx, w, h);
    }
}
