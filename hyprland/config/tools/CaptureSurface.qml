import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "CaptureGeometry.js" as Geometry

PanelWindow {
    id: window
    objectName: "captureSurface:" + display.name
    PillTheme { id: typography }
    required property var controller
    required property var display
    screen: Quickshell.screens.find(s => s.name === display.name) || Quickshell.screens[0]
    readonly property bool showing: controller.active && !controller.recording && display.width > 0 && display.height > 0
    // Keep a transparent, input-free surface at its final size while idle.
    // Resizing a 1px buffer on open can briefly stretch it across the monitor
    // before the compositor receives the new full-size frame.
    anchors { top: true; bottom: true; left: true; right: true }
    mask: Region { width: window.showing ? window.width : 0; height: window.showing ? window.height : 0 }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: controller.persistent || showing
    WlrLayershell.namespace: "dotfiles-capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: showing && current ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property string tool: controller.tool
    readonly property var strokes: controller.strokes
    readonly property color ink: controller.ink
    readonly property bool current: controller.current === display.name
    readonly property bool selected: controller.selected
    readonly property bool video: controller.data.mode === "record"
    readonly property var localSelection: Geometry.local(controller.selection, display)
    readonly property bool intersects: localSelection.width > 0 && localSelection.height > 0
    Connections {
        target: controller
        function onOpeningChanged() {
            if (!controller.opening) return;
            textInput.visible = false;
            textInput.focus = false;
            textInput.text = "";
            pointer.dragMode = "";
            pointer.startSelection = null;
            scene.focus = Qt.binding(() => window.current);
        }
    }
    function repaint() { selectionContent.repaint(); }
    function undo() { controller.undo(); }
    function insideSelection(x, y) {
        const rect = controller.selection;
        return selected && x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height;
    }
    function finish() {
        if (!selected || controller.exporting || controller.closePending || controller.recordPending || controller.dragging) return;
        if (textInput.visible) { textInput.commit(); return; }
        if (video) controller.beginRecording();
        else {
            const outputs = controller.data.outputs.filter(o => Geometry.valid(Geometry.intersect(controller.selection, o)));
            controller.exportImage(selectionContent, Math.max(...outputs.map(o => o.scale)));
        }
    }
    function command(event) {
        if (textInput.visible) return [Qt.Key_Escape, Qt.Key_Return, Qt.Key_Enter].includes(event.key);
        return true;
    }
    component ActionButton: Rectangle {
        id: button
        property string caption
        property string icon
        property string label: ""
        property bool chosen: false
        property bool checkable: false
        signal clicked()
        implicitHeight: 36; implicitWidth: 38
        color: chosen ? "#55423d3a" : "transparent"
        opacity: enabled ? 1 : 0.45
        radius: 10
        Accessible.role: checkable ? Accessible.CheckBox : Accessible.Button
        Accessible.name: caption
        Accessible.checkable: checkable
        Accessible.checked: checkable && chosen
        Accessible.onPressAction: clicked()
        Image { visible: !button.label; anchors.centerIn: parent; width: 19; height: 19; sourceSize: Qt.size(19, 19); source: button.icon ? Qt.resolvedUrl("icons/" + button.icon + ".svg") : "" }
        Text { visible: !!button.label; anchors.centerIn: parent; text: button.label; color: "#f4e9e2"; font.family: "Adwaita Sans"; font.pixelSize: 13; font.weight: Font.Medium }
        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: button.clicked() }
    }
    Item {
        id: scene
        visible: window.showing
        objectName: "captureScene:" + display.name
        anchors.fill: parent
        focus: window.current
        Keys.onShortcutOverride: event => { if (window.command(event)) event.accepted = true; }
        Keys.onPressed: event => {
            controller.keyPressed(event.key, event.modifiers, event.isAutoRepeat, event.nativeScanCode);
            if (controller.closePending || controller.recordPending) {
                event.accepted = true;
                if (event.key === Qt.Key_Escape && !event.isAutoRepeat) controller.closeSession();
            } else if (event.key === Qt.Key_Escape) {
                event.accepted = true;
                if (!event.isAutoRepeat) {
                    if (textInput.visible) { textInput.visible = false; scene.forceActiveFocus(); }
                    else controller.closeSession();
                }
            } else if (textInput.visible && [Qt.Key_Return, Qt.Key_Enter].includes(event.key)) {
                event.accepted = true;
                if (!event.isAutoRepeat) textInput.commit();
            } else if (!textInput.visible && [Qt.Key_Backspace, Qt.Key_Delete].includes(event.key)) {
                event.accepted = true;
                if (!event.isAutoRepeat) window.undo();
            } else if (window.command(event)) {
                event.accepted = true;
                if (!event.isAutoRepeat) window.finish();
            } else event.accepted = false;
        }
        Keys.onReleased: event => {
            const consume = controller.closePending || controller.recordPending || window.command(event);
            controller.keyReleased(event.key, event.isAutoRepeat, event.nativeScanCode);
            event.accepted = consume;
        }
        Connections {
            target: scene.Window.window
            function onFrameSwapped() {
                // Only count a complete overlay at the current output size.
                if (window.showing && Math.abs(window.width - display.width) < 1 && Math.abs(window.height - display.height) < 1)
                    controller.noteFrame(display.name);
            }
        }
        // Session URLs are unique. Share the decoded image with the selection
        // and blur layers rather than decoding each full monitor repeatedly.
        Image { anchors.fill: parent; source: controller.includeCursor ? display.cursor : display.plain; fillMode: Image.Stretch }
        CaptureContent {
            id: selectionContent
            controller: window.controller
            x: controller.selection.x - display.x; y: controller.selection.y - display.y
            visible: window.selected
        }
        Rectangle { width: scene.width; height: window.intersects ? window.localSelection.y : scene.height; color: "#99000000" }
        Rectangle { visible: window.intersects; x: 0; y: window.localSelection.y; width: window.localSelection.x; height: window.localSelection.height; color: "#99000000" }
        Rectangle { visible: window.intersects; x: window.localSelection.x + window.localSelection.width; y: window.localSelection.y; width: Math.max(0, scene.width - x); height: window.localSelection.height; color: "#99000000" }
        Rectangle { visible: window.intersects; x: 0; y: window.localSelection.y + window.localSelection.height; width: scene.width; height: Math.max(0, scene.height - y); color: "#99000000" }
        Rectangle {
            visible: window.selected
            x: controller.selection.x - display.x; y: controller.selection.y - display.y
            width: controller.selection.width; height: controller.selection.height
            color: "transparent"; border.color: "#cc7855"; border.width: 1
        }
        MouseArea {
            id: pointer
            objectName: "capturePointer"
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            hoverEnabled: true
            cursorShape: dragMode === "move" && pressed ? Qt.ClosedHandCursor
                : !window.tool && window.insideSelection(display.x + mouseX, display.y + mouseY) ? Qt.SizeAllCursor
                : window.tool === "text" && window.insideSelection(display.x + mouseX, display.y + mouseY) ? Qt.IBeamCursor : Qt.CrossCursor
            property real startX: 0
            property real startY: 0
            property string dragMode: ""
            property var startSelection: null
            function point(mouse) {
                const bounds = controller.desktopBounds;
                return {x: Math.round(Math.max(bounds.x, Math.min(bounds.x + bounds.width, display.x + mouse.x))),
                        y: Math.round(Math.max(bounds.y, Math.min(bounds.y + bounds.height, display.y + mouse.y)))};
            }
            function move(mouse) {
                const p = point(mouse);
                if (dragMode === "select") controller.selection = {x: Math.min(startX, p.x), y: Math.min(startY, p.y), width: Math.abs(p.x - startX), height: Math.abs(p.y - startY)};
                else if (dragMode === "move") {
                    const bounds = controller.desktopBounds;
                    controller.selection = {
                        x: Math.max(bounds.x, Math.min(bounds.x + bounds.width - startSelection.width, startSelection.x + p.x - startX)),
                        y: Math.max(bounds.y, Math.min(bounds.y + bounds.height - startSelection.height, startSelection.y + p.y - startY)),
                        width: startSelection.width, height: startSelection.height
                    };
                } else if (dragMode === "draw" && controller.draft) {
                    const draft = Object.assign({}, controller.draft, {x2: p.x, y2: p.y, points: controller.draft.points.concat([p])});
                    controller.draft = draft;
                }
            }
            function begin(mouse) {
                controller.dragging = true;
                const p = point(mouse); startX = p.x; startY = p.y;
                // Keep exclusive keyboard focus stable during a geometry drag:
                // changing it mid-press can cancel Wayland's pointer grab.
                const editingText = window.tool === "text" && mouse.button === Qt.LeftButton && window.insideSelection(p.x, p.y);
                if (!editingText && textInput.visible) {
                    textInput.visible = false;
                    if (window.current) scene.forceActiveFocus();
                }
                if (window.tool === "text" && mouse.button === Qt.LeftButton && window.insideSelection(p.x, p.y)) controller.current = display.name;
                startSelection = Object.assign({}, controller.selection);
                if (mouse.button === Qt.RightButton || !window.insideSelection(p.x, p.y)) {
                    dragMode = "select";
                    textInput.visible = false;
                    controller.selection = {x: p.x, y: p.y, width: 0, height: 0};
                } else if (!window.tool) {
                    dragMode = "move";
                    textInput.visible = false;
                } else {
                    dragMode = window.tool === "text" ? "text" : "draw";
                    if (dragMode === "text") {
                        textInput.x = mouse.x; textInput.y = mouse.y;
                        textInput.text = ""; textInput.visible = true; textInput.forceActiveFocus();
                    } else controller.draft = {type: window.tool, x: p.x, y: p.y, x2: p.x, y2: p.y, color: window.ink.toString(), points: [p]};
                }
            }
            onPositionChanged: mouse => { if (pressed) move(mouse); }
            function end(mouse) {
                move(mouse);
                if (controller.draft) { controller.strokes = controller.strokes.concat([controller.draft]); controller.draft = null; }
                if (dragMode !== "text") {
                    const p = point(mouse), output = controller.data.outputs.find(o => p.x >= o.x && p.x < o.x + o.width && p.y >= o.y && p.y < o.y + o.height);
                    if (output) controller.current = output.name;
                }
                if (dragMode === "select" || dragMode === "move") controller.remember();
                dragMode = "";
                controller.dragging = false;
                Qt.callLater(() => controller.finishInput());
            }
            function cancel() { controller.draft = null; dragMode = ""; controller.dragging = false; Qt.callLater(() => controller.finishInput()); }
            onPressed: mouse => begin(mouse)
            onReleased: mouse => end(mouse)
            onCanceled: cancel()
        }
        TextField {
            id: textInput
            objectName: "captureAnnotationInput"
            font: typography.textFont
            Keys.forwardTo: [scene]
            visible: false; width: Math.min(380, scene.width - x)
            color: window.ink
            placeholderText: "Type a label, then Enter"
            background: Rectangle {
                color: typography.background; radius: 8
                border.width: 1; border.color: typography.border
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
                    height: 2; radius: 1; color: typography.focusColor
                    visible: textInput.activeFocus
                }
            }
            function commit() {
                if (text.length) controller.strokes = controller.strokes.concat([{type: "text", x: display.x + x + leftPadding, y: display.y + y + topPadding, text: text, color: window.ink.toString()}]);
                visible = false; scene.forceActiveFocus();
            }
            onAccepted: commit()
        }
        Item {
            id: toolbar
            objectName: "captureToolbar"
            visible: window.current && window.selected && !controller.dragging
            readonly property int buttonCount: toolButtons.count + inkButtons.count + 1 + (window.video ? 4 : 0)
            readonly property var horizontalSize: ({width: Math.min(scene.width - 16,
                toolButtons.count * 38 + inkButtons.count * 24 + 38 + (window.video ? 152 : 0) + (buttonCount - 1) * controls.spacing + 20), height: 54})
            readonly property var verticalSize: ({width: 58, height: Math.min(scene.height - 16, buttonCount * 36 + (buttonCount - 1) * controls.spacing + 20)})
            readonly property var placement: Geometry.toolbar(window.localSelection, scene.width, scene.height, horizontalSize, verticalSize)
            readonly property bool vertical: placement.vertical
            x: placement.x; y: placement.y
            width: placement.width; height: placement.height
            PillBackground { anchors.fill: parent; theme: typography; radius: 20 }
            Flickable {
                anchors.fill: parent; anchors.margins: 8; clip: true
                contentWidth: controls.implicitWidth; contentHeight: controls.implicitHeight
                flickableDirection: toolbar.vertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick; boundsBehavior: Flickable.StopAtBounds
                Grid {
                    id: controls
                    columns: toolbar.vertical ? 1 : toolbar.buttonCount
                    horizontalItemAlignment: Grid.AlignHCenter
                    spacing: 5
                    Repeater {
                        id: toolButtons
                        objectName: "captureTools"
                        model: window.video ? [] : ["pen", "arrow", "box", "text", "blur"]
                        ActionButton {
                            required property string modelData
                            objectName: "captureTool:" + modelData
                            caption: modelData[0].toUpperCase() + modelData.slice(1)
                            icon: ({pen:"pen-line", arrow:"move-up-right", box:"square", text:"type", blur:"opacity"})[modelData]
                            chosen: window.tool === modelData
                            onClicked: controller.tool = controller.tool === modelData ? "" : modelData
                        }
                    }
                    Repeater {
                        id: inkButtons
                        model: window.video ? [] : ["#cc7855", "#ed9c87", "#e4c393", "#ffffff"]
                        Rectangle {
                            required property string modelData
                            width: 24; height: 36; radius: 7; color: modelData
                            border.width: window.ink.toString() === modelData ? 2 : 0; border.color: typography.focusColor
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: controller.ink = parent.modelData }
                        }
                    }
                    ActionButton { caption: "Cursor " + (controller.includeCursor ? "On" : "Off"); icon: controller.includeCursor ? "mouse-pointer-2" : "mouse-pointer-2-off"; chosen: controller.includeCursor; onClicked: { controller.includeCursor = !controller.includeCursor; controller.remember(); } }
                    ActionButton { objectName: "captureSpeakersButton"; visible: window.video; checkable: true; caption: "Record speakers " + (controller.recordSpeakers ? "On" : "Off"); icon: controller.recordSpeakers ? "volume-2" : "volume-x"; chosen: controller.recordSpeakers; onClicked: { controller.recordSpeakers = !controller.recordSpeakers; controller.remember(); } }
                    ActionButton { objectName: "captureMicButton"; visible: window.video; checkable: true; caption: "Record mic " + (controller.recordMic ? "On" : "Off"); icon: controller.recordMic ? "mic" : "mic-off"; chosen: controller.recordMic; onClicked: { controller.recordMic = !controller.recordMic; controller.remember(); } }
                    ActionButton { objectName: "captureFpsButton"; visible: window.video; caption: "Frame rate " + controller.recordFps + " FPS"; label: String(controller.recordFps); onClicked: controller.cycleRecordingFps() }
                    ActionButton { objectName: "captureRecordButton"; visible: window.video; caption: "Start recording"; icon: "video"; onClicked: window.finish() }
                }
            }
        }
        Rectangle {
            visible: controller.error.length > 0
            anchors { top: parent.top; topMargin: 18; horizontalCenter: parent.horizontalCenter }
            width: Math.min(scene.width - 32, status.implicitWidth + 30); height: status.implicitHeight + 20; radius: 20
            color: typography.background
            Text { id: status; width: parent.width - 30; anchors.centerIn: parent; text: controller.error; wrapMode: Text.Wrap; font: typography.textFont; color: typography.red }
        }
        MouseArea {
            anchors.fill: parent
            z: 100
            acceptedButtons: Qt.RightButton
            preventStealing: true
            cursorShape: Qt.CrossCursor
            onPressed: mouse => pointer.begin(mouse)
            onPositionChanged: mouse => { if (pressed) pointer.move(mouse); }
            onReleased: mouse => pointer.end(mouse)
            onCanceled: pointer.cancel()
        }

    }
}
