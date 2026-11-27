.pragma library

function bounds(outputs) {
    const x = Math.min(...outputs.map(o => o.x)), y = Math.min(...outputs.map(o => o.y));
    return {x: x, y: y, width: Math.max(...outputs.map(o => o.x + o.width)) - x,
            height: Math.max(...outputs.map(o => o.y + o.height)) - y};
}
function intersect(a, b) {
    const x = Math.max(a.x, b.x), y = Math.max(a.y, b.y);
    return {x: x, y: y, width: Math.max(0, Math.min(a.x + a.width, b.x + b.width) - x),
            height: Math.max(0, Math.min(a.y + a.height, b.y + b.height) - y)};
}
function valid(rect) {
    return !!rect && [rect.x, rect.y, rect.width, rect.height].every(Number.isFinite) && rect.width >= 2 && rect.height >= 2;
}
function restore(rect, outputs) {
    if (!valid(rect)) return {x: 0, y: 0, width: 0, height: 0};
    const clipped = intersect(rect, bounds(outputs));
    return valid(clipped) && outputs.some(o => valid(intersect(clipped, o))) ? clipped : {x: 0, y: 0, width: 0, height: 0};
}
function local(rect, output) {
    const clipped = intersect(rect, output);
    return {x: clipped.x - output.x, y: clipped.y - output.y, width: clipped.width, height: clipped.height};
}

function toolbar(rect, screenWidth, screenHeight, horizontal, vertical) {
    const margin = 8, gap = 12;
    function clamp(value, size, limit) { return Math.max(margin, Math.min(limit - size - margin, value)); }
    function candidate(side, x, y, size, upright) {
        return {side: side, x: Math.round(x), y: Math.round(y), width: size.width, height: size.height, vertical: upright};
    }
    function fits(item) {
        return item.x >= margin && item.y >= margin
            && item.x + item.width <= screenWidth - margin && item.y + item.height <= screenHeight - margin;
    }
    const centerX = clamp(rect.x + (rect.width - horizontal.width) / 2, horizontal.width, screenWidth);
    const centerY = clamp(rect.y + (rect.height - vertical.height) / 2, vertical.height, screenHeight);
    const candidates = [
        candidate("bottom", centerX, rect.y + rect.height + gap, horizontal, false),
        candidate("top", centerX, rect.y - horizontal.height - gap, horizontal, false),
        candidate("left", rect.x - vertical.width - gap, centerY, vertical, true),
        candidate("right", rect.x + rect.width + gap, centerY, vertical, true)
    ];
    return candidates.find(fits) || candidate("inner-top", centerX,
        clamp(rect.y + gap, horizontal.height, screenHeight), horizontal, false);
}

// Side under the pointer, so a press near an edge drags that side instead of
// starting a new selection. Corners are left to the plain select gesture.
function edgeAt(rect, x, y, tolerance) {
    if (!valid(rect)) return "";
    const left = rect.x, right = rect.x + rect.width, top = rect.y, bottom = rect.y + rect.height;
    const withinX = x > left + tolerance && x < right - tolerance;
    const withinY = y > top + tolerance && y < bottom - tolerance;
    if (withinX && Math.abs(y - top) <= tolerance) return "top";
    if (withinX && Math.abs(y - bottom) <= tolerance) return "bottom";
    if (withinY && Math.abs(x - left) <= tolerance) return "left";
    if (withinY && Math.abs(x - right) <= tolerance) return "right";
    return "";
}
function resize(start, edge, point) {
    let left = start.x, right = start.x + start.width, top = start.y, bottom = start.y + start.height;
    if (edge === "left") left = point.x;
    else if (edge === "right") right = point.x;
    else if (edge === "top") top = point.y;
    else if (edge === "bottom") bottom = point.y;
    return {x: Math.min(left, right), y: Math.min(top, bottom), width: Math.abs(right - left), height: Math.abs(bottom - top)};
}
