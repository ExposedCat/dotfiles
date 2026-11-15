import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

// Each blur samples the complete earlier image. Ordinary annotations after it
// stay sharp; earlier annotations are blurred along with the frozen desktop.
Item {
    id: root
    property var controller: null
    property var strokes: []
    property int limit: 0
    readonly property var selection: controller ? controller.selection : ({x:0,y:0,width:1,height:1})
    readonly property int blurIndex: {
        for (let i = Math.min(limit, strokes.length) - 1; i >= 0; --i)
            if (strokes[i].type === "blur") return i;
        return -1;
    }
    readonly property var blurStroke: blurIndex >= 0 ? strokes[blurIndex] : null
    readonly property real blurX: blurStroke ? Math.min(blurStroke.x, blurStroke.x2) - selection.x : 0
    readonly property real blurY: blurStroke ? Math.min(blurStroke.y, blurStroke.y2) - selection.y : 0
    readonly property real blurWidth: blurStroke ? Math.abs(blurStroke.x2 - blurStroke.x) : 0
    readonly property real blurHeight: blurStroke ? Math.abs(blurStroke.y2 - blurStroke.y) : 0
    // Include neighbouring pixels so blur does not fade at the patch edges.
    readonly property rect sampleRect: {
        const left = Math.max(0, blurX - 128), top = Math.max(0, blurY - 128);
        const right = Math.min(width, blurX + blurWidth + 128), bottom = Math.min(height, blurY + blurHeight + 128);
        return Qt.rect(left, top, Math.max(1, right - left), Math.max(1, bottom - top));
    }
    readonly property real imageScale: controller && controller.data.outputs.length ? Math.max(...controller.data.outputs.map(o => o.scale)) : 1
    clip: true
    function repaint() { drawing.requestPaint(); if (before.item) before.item.repaint(); }
    onStrokesChanged: drawing.requestPaint()
    onLimitChanged: drawing.requestPaint()
    onSelectionChanged: drawing.requestPaint()

    Loader {
        anchors.fill: parent
        active: root.blurIndex < 0
        sourceComponent: Item {
            Rectangle { anchors.fill: parent; color: "black" }
            Repeater {
                model: root.controller ? root.controller.data.outputs : []
                Image {
                    required property var modelData
                    x: modelData.x - root.selection.x; y: modelData.y - root.selection.y
                    width: modelData.width; height: modelData.height
                    source: root.controller.includeCursor ? modelData.cursor : modelData.plain
                    fillMode: Image.Stretch; cache: false
                }
            }
        }
    }
    Loader {
        id: before
        anchors.fill: parent
        active: root.blurIndex >= 0
        source: "CaptureLayer.qml"
        onLoaded: {
            item.controller = Qt.binding(() => root.controller);
            item.strokes = Qt.binding(() => root.strokes);
            item.limit = Qt.binding(() => root.blurIndex);
        }
    }
    ShaderEffectSource {
        id: sample
        visible: false
        sourceItem: before.item
        sourceRect: root.sampleRect
        width: root.sampleRect.width; height: root.sampleRect.height
        textureSize: Qt.size(Math.ceil(width * root.imageScale), Math.ceil(height * root.imageScale))
        live: true
    }
    ClippingRectangle {
        visible: root.blurIndex >= 0 && root.blurWidth > 0 && root.blurHeight > 0
        x: root.blurX; y: root.blurY; width: root.blurWidth; height: root.blurHeight
        radius: Math.min(8, width / 2, height / 2)
        color: "transparent"
        MultiEffect {
            x: root.sampleRect.x - root.blurX; y: root.sampleRect.y - root.blurY
            width: root.sampleRect.width; height: root.sampleRect.height
            source: sample
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: 1
            blurMultiplier: 0.5
        }
    }
    Canvas {
        id: drawing
        x: 0; y: 0
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.save(); ctx.translate(-root.selection.x, -root.selection.y);
            const items = root.strokes.slice(root.blurIndex + 1, root.limit);
            for (const item of items) {
                ctx.strokeStyle = item.color;
                ctx.fillStyle = item.color;
                ctx.lineWidth = 3;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                const dx = item.x2 - item.x, dy = item.y2 - item.y;
                if (item.type === "box") {
                    ctx.strokeRect(item.x, item.y, dx, dy);
                } else if (item.type === "arrow") {
                    ctx.beginPath(); ctx.moveTo(item.x, item.y); ctx.lineTo(item.x2, item.y2); ctx.stroke();
                    const angle = Math.atan2(dy, dx), head = 14;
                    ctx.beginPath(); ctx.moveTo(item.x2, item.y2);
                    ctx.lineTo(item.x2 - head * Math.cos(angle - Math.PI / 6), item.y2 - head * Math.sin(angle - Math.PI / 6));
                    ctx.lineTo(item.x2 - head * Math.cos(angle + Math.PI / 6), item.y2 - head * Math.sin(angle + Math.PI / 6));
                    ctx.closePath(); ctx.fill();
                } else if (item.type === "pen") {
                    ctx.beginPath();
                    item.points.forEach((p, index) => { if (index === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y) });
                    ctx.stroke();
                } else if (item.type === "text") {
                    ctx.font = 18 + 'px "' + "Adwaita Sans" + '"';
                    ctx.fillText(item.text, item.x, item.y + 18);
                }
            }
            ctx.restore();
        }
    }
}
