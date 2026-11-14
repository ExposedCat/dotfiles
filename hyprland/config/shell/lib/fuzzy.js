// Adapted from Ricelin, copyright (c) 2026 Gakuseei. MIT; see ../RICELIN-LICENSE.txt.
function haystacks(e) {
    var parts = [];
    if (e.name) parts.push(String(e.name));
    if (e.description) parts.push(String(e.description));
    if (e.genericName) parts.push(String(e.genericName));
    if (e.keywords) for (var i = 0; i < e.keywords.length; i++) parts.push(String(e.keywords[i]));
    return parts;
}

function subsequence(needle, hay) {
    var j = 0;
    for (var i = 0; i < hay.length && j < needle.length; i++)
        if (hay[i] === needle[j]) j++;
    return j === needle.length;
}

// Prefer compact subsequences over letters scattered across the whole name.
function subsequenceCost(needle, hay) {
    var best = 1;
    for (var start = 0; start < hay.length; start++) {
        if (hay[start] !== needle[0]) continue;
        var at = start + 1, matched = true;
        for (var j = 1; j < needle.length; j++) {
            at = hay.indexOf(needle[j], at);
            if (at < 0) { matched = false; break; }
            at++;
        }
        if (matched) best = Math.min(best, Math.min(0.9, (at - start - needle.length) * 0.03 + start * 0.005));
    }
    return best;
}

function score(e, q) {
    var name = (e.name || "").toLowerCase();
    if (name.indexOf(q) === 0) return 0;
    var fields = haystacks(e);
    var best = 99;
    for (var i = 0; i < fields.length; i++) {
        var f = fields[i].toLowerCase();
        if (f.indexOf(q) !== -1) { best = Math.min(best, 1); continue; }
        if (subsequence(q, f)) best = Math.min(best, 2 + subsequenceCost(q, f));
    }
    return best;
}

function uses(usage, e) {
    if (!usage || !e || !e.id) return 0;
    var c = usage[e.id];
    return typeof c === "number" ? c : 0;
}

function rank(entries, query, usage) {
    usage = usage || {};
    var visible = [];
    for (var i = 0; i < entries.length; i++)
        if (!entries[i].noDisplay) visible.push(entries[i]);

    var q = (query || "").trim().toLowerCase();
    if (q.length === 0)
        return visible.slice().sort(function (a, b) {
            var ua = uses(usage, a);
            var ub = uses(usage, b);
            if (ua !== ub) return ub - ua;
            return (a.name || "").toLowerCase().localeCompare((b.name || "").toLowerCase());
        });

    var scored = [];
    for (var k = 0; k < visible.length; k++) {
        var s = score(visible[k], q);
        if (s < 99) scored.push({ e: visible[k], s: s });
    }
    scored.sort(function (a, b) {
        if (a.s !== b.s) return a.s - b.s;
        var ua = uses(usage, a.e);
        var ub = uses(usage, b.e);
        if (ua !== ub) return ub - ua;
        return (a.e.name || "").toLowerCase().localeCompare((b.e.name || "").toLowerCase());
    });
    return scored.map(function (x) { return x.e; });
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { rank, score, subsequence };
}
