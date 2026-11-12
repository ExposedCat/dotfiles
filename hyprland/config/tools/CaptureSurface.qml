import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window
    required property var controller
    required property var display
    screen: Quickshell.screens.find(s => s.name === display.name) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    color: "transparent"
    visible: !controller.recording
    WlrLayershell.namespace: "dotfiles-capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: controller.current === display.name ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property real selectionX: 0
    property real selectionY: 0
    property real selectionWidth: 0
    property real selectionHeight: 0
    property string tool: "select"
    property color ink: "#89b4fa"
    property var strokes: []
    property var draft: null
    readonly property bool current: controller.current === display.name
    readonly property bool selected: current && selectionWidth >= 2 && selectionHeight >= 2
    readonly property bool video: controller.data.mode === "record"

    function repaint() { drawing.requestPaint(); }
    function finish() {
        if (!selected || controller.exporting) return;
        if (textInput.visible) { textInput.commit(); return; }
        if (video) controller.beginRecording(display, selectionX, selectionY, selectionWidth, selectionHeight);
        else controller.exportImage(selectionContent, display.scale);
    }
    function undo() { strokes = strokes.slice(0, -1); repaint(); }
    Component.onCompleted: {
        const selection = controller.data.selection;
        if (selection && selection.monitor === display.name) {
            selectionX = selection.x; selectionY = selection.y;
            selectionWidth = selection.width; selectionHeight = selection.height;
        }
    }

    component ActionButton: Rectangle {
        property string caption
        property bool chosen: false
        signal clicked()
        implicitHeight: 34
        implicitWidth: captionLabel.implicitWidth + 22
        color: chosen ? "#89b4fa" : hover.containsMouse ? "#45475a" : "#313244"
        opacity: enabled ? 1 : 0.45
        radius: 8
        Text { id: captionLabel; anchors.centerIn: parent; text: parent.caption; color: parent.chosen ? "#1e1e2e" : "#cdd6f4"; font.pixelSize: 13 }
        MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; onClicked: parent.clicked() }
    }

    Item {
        id: scene
        anchors.fill: parent
        focus: window.current
        Image {
            anchors.fill: parent
            source: controller.includeCursor ? display.cursor : display.plain
            fillMode: Image.Stretch
        }

        // Only this item is exported. Selection borders, handles, and toolbars
        // are siblings and therefore cannot appear in the saved image.
        Item {
            id: selectionContent
            x: window.selectionX; y: window.selectionY
            width: window.selectionWidth; height: window.selectionHeight
            visible: window.selected
            clip: true
            Image {
                x: -window.selectionX; y: -window.selectionY
                width: scene.width; height: scene.height
                source: controller.includeCursor ? display.cursor : display.plain
                fillMode: Image.Stretch
            }
            Canvas {
                id: drawing
                x: -window.selectionX; y: -window.selectionY
                width: scene.width; height: scene.height
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const items = window.draft ? window.strokes.concat([window.draft]) : window.strokes;
                    for (const item of items) {
                        ctx.strokeStyle = item.color;
                        ctx.fillStyle = item.color;
                        ctx.lineWidth = 3;
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        const dx = item.x2 - item.x, dy = item.y2 - item.y;
                        if (item.type === "redact") {
                            ctx.fillStyle = "#111111";
                            ctx.fillRect(Math.min(item.x, item.x2), Math.min(item.y, item.y2), Math.abs(dx), Math.abs(dy));
                        } else if (item.type === "box") {
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
                            item.points.forEach((p, index) => { if (index === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y); });
                            ctx.stroke();
                        } else if (item.type === "text") {
                            ctx.font = "24px sans-serif";
                            ctx.fillText(item.text, item.x, item.y + 24);
                        }
                    }
                }
            }
        }

        Rectangle { width: scene.width; height: window.selected ? window.selectionY : scene.height; color: "#99000000" }
        Rectangle { visible: window.selected; x: 0; y: window.selectionY; width: window.selectionX; height: window.selectionHeight; color: "#99000000" }
        Rectangle { visible: window.selected; x: window.selectionX + window.selectionWidth; y: window.selectionY; width: Math.max(0, scene.width - x); height: window.selectionHeight; color: "#99000000" }
        Rectangle { visible: window.selected; x: 0; y: window.selectionY + window.selectionHeight; width: scene.width; height: Math.max(0, scene.height - y); color: "#99000000" }
        Rectangle {
            visible: window.selected
            x: window.selectionX; y: window.selectionY
            width: window.selectionWidth; height: window.selectionHeight
            color: "transparent"
            border.color: "#89b4fa"
            border.width: 1
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            cursorShape: window.tool === "select" ? Qt.CrossCursor : window.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
            property real startX: 0
            property real startY: 0
            onPressed: mouse => {
                controller.current = display.name;
                startX = Math.floor(mouse.x); startY = Math.floor(mouse.y);
                if (window.tool === "select") {
                    textInput.visible = false;
                    window.selectionX = startX; window.selectionY = startY;
                    window.selectionWidth = 0; window.selectionHeight = 0;
                } else if (window.selected && mouse.x >= window.selectionX && mouse.x <= window.selectionX + window.selectionWidth
                           && mouse.y >= window.selectionY && mouse.y <= window.selectionY + window.selectionHeight) {
                    if (window.tool === "text") {
                        textInput.x = mouse.x; textInput.y = mouse.y;
                        textInput.text = ""; textInput.visible = true; textInput.forceActiveFocus();
                    } else {
                        window.draft = { type: window.tool, x: startX, y: startY, x2: startX, y2: startY,
                            color: window.ink.toString(), points: [{ x: startX, y: startY }] };
                    }
                }
            }
            onPositionChanged: mouse => {
                if (!pressed) return;
                const x = Math.round(Math.max(0, Math.min(scene.width, mouse.x)));
                const y = Math.round(Math.max(0, Math.min(scene.height, mouse.y)));
                if (window.tool === "select") {
                    window.selectionX = Math.min(startX, x); window.selectionY = Math.min(startY, y);
                    window.selectionWidth = Math.abs(x - startX); window.selectionHeight = Math.abs(y - startY);
                } else if (window.draft) {
                    window.draft.x2 = x; window.draft.y2 = y;
                    window.draft.points.push({ x: x, y: y }); window.repaint();
                }
            }
            onReleased: {
                if (window.draft) { window.strokes = window.strokes.concat([window.draft]); window.draft = null; window.repaint(); }
            }
        }
        TextField {
            id: textInput
            visible: false
            width: Math.min(380, scene.width - x)
            color: window.ink
            font.pixelSize: 24
            placeholderText: "Type a label, then Enter"
            background: Rectangle { color: "#e61e1e2e"; radius: 6; border.color: "#89b4fa" }
            function commit() {
                if (text.length) window.strokes = window.strokes.concat([{type: "text", x: x + leftPadding, y: y + topPadding, text: text, color: window.ink.toString()}]);
                visible = false; scene.forceActiveFocus(); window.repaint();
            }
            onAccepted: commit()
        }
        Rectangle {
            id: toolbar
            visible: window.selected
            x: Math.max(12, (scene.width - width) / 2)
            y: window.selected ? (window.selectionY + window.selectionHeight + height + 24 < scene.height
                ? window.selectionY + window.selectionHeight + 12 : Math.max(12, window.selectionY - height - 12)) : scene.height - height - 28
            width: controls.width + 20
            height: 54
            color: "#f51e1e2e"
            border.color: "#45475a"
            radius: 12
            Row {
                id: controls
                anchors.centerIn: parent
                spacing: 5
                ActionButton { caption: "Select"; chosen: window.tool === "select"; onClicked: window.tool = "select" }
                Repeater {
                    model: window.video ? [] : ["pen", "arrow", "box", "text", "redact"]
                    delegate: ActionButton {
                        required property string modelData
                        caption: modelData[0].toUpperCase() + modelData.slice(1)
                        chosen: window.tool === modelData
                        enabled: window.selected
                        onClicked: window.tool = modelData
                    }
                }
                Repeater {
                    model: window.video ? [] : ["#89b4fa", "#f38ba8", "#f9e2af", "#ffffff"]
                    delegate: Rectangle {
                        required property string modelData
                        width: 24; height: 34; radius: 7
                        color: modelData
                        border.width: window.ink.toString() === modelData ? 3 : 0
                        border.color: "#6c7086"
                        MouseArea { anchors.fill: parent; onClicked: window.ink = parent.modelData }
                    }
                }
                ActionButton { visible: !window.video; caption: "Undo"; enabled: window.strokes.length > 0; onClicked: window.undo() }
                ActionButton { caption: "Cursor " + (controller.includeCursor ? "On" : "Off"); chosen: controller.includeCursor; onClicked: controller.includeCursor = !controller.includeCursor }
                ActionButton { caption: window.video ? "Record" : controller.exporting ? "Copying…" : "Copy + Save"; chosen: true; enabled: window.selected && !controller.exporting; onClicked: window.finish() }
                ActionButton { caption: "Cancel"; onClicked: Qt.quit() }
            }
        }
        Rectangle {
            visible: controller.error.length > 0
            anchors.top: parent.top
            anchors.topMargin: 18
            anchors.horizontalCenter: parent.horizontalCenter
            width: status.implicitWidth + 30; height: 38; radius: 10
            color: "#e61e1e2e"
            Text {
                id: status
                anchors.centerIn: parent
                text: controller.error
                color: "#f38ba8"
                font.pixelSize: 14
            }
        }
        Shortcut { sequence: "Escape"; enabled: window.current; onActivated: { if (textInput.visible) textInput.visible = false; else Qt.quit(); } }
        Shortcut { sequence: "Return"; enabled: window.current && !textInput.visible; onActivated: window.finish() }
        Shortcut { sequence: "Ctrl+C"; enabled: window.current && !textInput.visible && !window.video; onActivated: window.finish() }
        Shortcut { sequence: "Ctrl+Z"; enabled: window.current && !textInput.visible && !window.video; onActivated: window.undo() }
    }
}
