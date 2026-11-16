import QtQuick
import QtQuick.Controls

Item {
    id: root
    required property var shell
    required property var theme
    required property string metric
    property string label: metric
    property var samples: []
    property var value: null
    property real endTime: 0
    property bool selected: false
    property int inspectionIndex: -1
    readonly property real duration: 60000
    readonly property real startTime: {
        const first = samples.find(sample => sample.time >= endTime - duration && sample.time <= endTime && valid(sample[metric]));
        return first ? first.time : endTime;
    }
    readonly property real timeSpan: Math.max(0, endTime - startTime)
    readonly property real inset: 4
    readonly property color traceColor: selected ? "#cc7855" : theme.text
    readonly property bool available: valid(value)
    readonly property Item emberSlot: endpoint
    readonly property var segments: makeSegments()
    readonly property var inspected: pointer.hovered ? sampleAt(pointer.point.position.x) : inspectionIndex >= 0 ? samples[inspectionIndex] : null
    readonly property bool pointerInside: pointer.hovered
    signal hovered()
    implicitHeight: 52
    objectName: "systemHistory:" + metric
    Accessible.role: Accessible.Chart
    Accessible.name: label + " usage over " + Math.round(timeSpan / 1000) + " seconds, from 0 to 100 percent, oldest samples on the left and newest on the right"
    function valid(number) { return typeof number === "number" && Number.isFinite(number); }
    function sampleX(time) { return inset + (width - inset * 2) * (time - startTime) / duration; }
    function sampleY(number) { return inset + (height - inset * 2) * (1 - Math.max(0, Math.min(100, number)) / 100); }
    function makeSegments() {
        const result = [];
        let segment = [], previousTime = 0;
        for (const sample of samples) {
            if (sample.time < endTime - duration || sample.time > endTime) continue;
            if (!valid(sample[metric]) || (previousTime && sample.time - previousTime > 2500)) {
                if (segment.length) result.push(segment);
                segment = [];
            }
            if (valid(sample[metric])) segment.push({x: sampleX(sample.time), y: sampleY(sample[metric])});
            previousTime = sample.time;
        }
        if (segment.length) result.push(segment);
        return result;
    }
    function sampleAt(x) {
        const tipX = sampleX(endTime);
        if (x < inset - 4 || x > tipX + 4) return null;
        const time = startTime + duration * (Math.max(inset, Math.min(tipX, x)) - inset) / Math.max(1, width - inset * 2);
        let nearest = null, distance = 2500;
        for (const sample of samples) {
            const delta = Math.abs(sample.time - time);
            if (valid(sample[metric]) && sample.time >= endTime - duration && delta < distance) {
                nearest = sample; distance = delta;
            }
        }
        return nearest;
    }
    function moveInspection(direction) {
        const step = direction;
        let index = inspectionIndex < 0 ? samples.length - 1 : inspectionIndex + step;
        while (index >= 0 && index < samples.length && !valid(samples[index][metric])) index += step;
        if (index >= 0 && index < samples.length) inspectionIndex = index;
    }
    onSamplesChanged: inspectionIndex = -1
    onSegmentsChanged: plot.requestPaint()
    onTraceColorChanged: plot.requestPaint()
    Canvas {
        id: plot
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = Qt.alpha(root.theme.text, 0.10);
            ctx.lineWidth = 1;
            for (const value of [0, 50, 100]) {
                ctx.beginPath(); ctx.moveTo(root.inset, root.sampleY(value)); ctx.lineTo(width - root.inset, root.sampleY(value)); ctx.stroke();
            }
            for (const points of root.segments) {
                if (points.length < 2) continue;
                ctx.beginPath(); ctx.moveTo(points[0].x, height - root.inset);
                for (const point of points) ctx.lineTo(point.x, point.y);
                ctx.lineTo(points[points.length - 1].x, height - root.inset); ctx.closePath();
                ctx.fillStyle = Qt.alpha(root.traceColor, root.selected ? 0.16 : 0.07); ctx.fill();
                ctx.beginPath(); ctx.moveTo(points[0].x, points[0].y);
                for (let i = 1; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y);
                ctx.strokeStyle = root.traceColor; ctx.lineWidth = 1.6; ctx.lineJoin = "bevel"; ctx.lineCap = "round"; ctx.stroke();
            }
        }
    }
    EmberSlot {
        id: endpoint
        objectName: "systemEndpoint:" + root.metric
        shell: root.shell
        width: 8; height: 8
        x: root.sampleX(root.endTime) - width / 2
        y: (root.available ? root.sampleY(root.value) : root.height / 2) - height / 2
        shapeRadius: 4; shapeOpacity: root.available ? 1 : 0
        Rectangle { anchors.fill: parent; radius: 4; visible: root.available; color: endpoint.occupied ? "transparent" : root.traceColor }
    }
    Rectangle {
        visible: !!root.inspected
        x: root.inspected ? root.sampleX(root.inspected.time) : 0
        y: root.inset; width: 1; height: parent.height - root.inset * 2
        color: Qt.alpha(root.theme.text, 0.35)
    }
    Rectangle {
        visible: !!root.inspected
        x: root.inspected ? root.sampleX(root.inspected.time) - width / 2 : 0
        y: root.inspected ? root.sampleY(root.inspected[root.metric]) - height / 2 : 0
        width: 6; height: 6; radius: 3; color: root.traceColor
    }
    HoverHandler { id: pointer; onHoveredChanged: { if (hovered) root.hovered(); } }
    ToolTip {
        id: inspectionTip
        visible: !!root.inspected
        text: root.inspected ? root.label + " · " + Math.round(root.inspected[root.metric]) + "% · " + (Math.max(0, Math.round((root.endTime - root.inspected.time) / 1000)) === 0 ? "Now" : Math.round((root.endTime - root.inspected.time) / 1000) + "s ago") : ""
        font: root.theme.textFont; padding: 8
        x: Math.max(0, Math.min(root.width - width, (root.inspected ? root.sampleX(root.inspected.time) : 0) - width / 2)); y: -height - 8
        background: Rectangle { color: root.theme.background; radius: 8; border.color: root.theme.hover }
        contentItem: Text { text: inspectionTip.text; font: root.theme.textFont; color: root.theme.text }
    }
}
