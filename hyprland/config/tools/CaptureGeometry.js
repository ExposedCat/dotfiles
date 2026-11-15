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
