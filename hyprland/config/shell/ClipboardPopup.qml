import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: root
    required property var shell
    required property var theme
    property var entries: []
    property var location: null
    property rect origin: Qt.rect(0, 0, 0, 0)
    property bool opened: false
    property bool loading: false
    property string error: ""
    property var focusGrab: null
    property real motion: 0
    property real initialReveal: 0
    property int closingSelection: -1
    readonly property real progress: initialReveal + ((opened ? 1 : 0) - initialReveal) * motion
    readonly property rect geometry: Qt.rect(body.x, body.y, body.width, body.height)
    readonly property rect destination: opened ? Qt.rect(targetX, targetY, listWidth, listHeight)
        : Qt.rect(origin.x, origin.y + origin.height, origin.width, 0)
    readonly property int margin: 8
    readonly property int entryGap: theme.panelGap
    readonly property int buttonSize: 36
    readonly property real listWidth: Math.max(1, Math.min(384, width - 3 * margin - buttonSize))
    readonly property real listHeight: Math.max(1, Math.min(height - 2 * margin, 531,
        Math.max(56, rowSizes.implicitHeight + 2 * entryGap)))
    readonly property real caretX: (location?.x ?? 0) - (screen?.x ?? 0)
    readonly property real caretTop: (location?.top ?? 0) - (screen?.y ?? 0)
    readonly property real caretBottom: (location?.bottom ?? 0) - (screen?.y ?? 0)
    readonly property bool fitsRight: caretX + listWidth + buttonSize + 2 * margin <= width
    readonly property real targetX: fitsRight
        ? clamp(caretX, margin, width - listWidth - buttonSize - 2 * margin)
        : clamp(caretX, 2 * margin + buttonSize, width - listWidth - margin)
    readonly property real targetY: caretBottom + listHeight + 2 * margin <= height
        ? Math.max(margin, caretBottom + margin)
        : clamp(caretTop - listHeight - margin, margin, height - listHeight - margin)

    visible: progress > 0 || opened
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "dotfiles-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: !opened ? WlrKeyboardFocus.None
        : shell.fixture ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    mask: Region { regions: root.opened ? [bodyInput, clearInput] : [] }
    Region { id: bodyInput; item: body }
    Region { id: clearInput; item: clearButton }
    NumberAnimation {
        id: transition
        target: root; property: "motion"; from: 0; to: 1
        duration: 220
        easing.type: Easing.InOutCubic
        onFinished: {
            if (root.opened) return;
            root.entries = [];
            clipboardEmber.hasPosition = false;
        }
    }

    function clamp(value, min, max) { return Math.max(min, Math.min(max, value)); }
    function blend(start, end) { return Math.round(start + (end - start) * motion); }
    function animate(from, reveal, opening) {
        transition.stop();
        origin = from;
        initialReveal = reveal;
        motion = 0;
        opened = opening;
        transition.start();
    }
    function isImage(entry) { return ["image", "remote-image"].includes(entry.kind); }
    function rowHeight(entry, richHeight) {
        if (isImage(entry)) return 150 + (entry.source ? 32 : 0);
        if (entry.kind === "html") return clamp(richHeight, 44, 86);
        return entry.kind === "video" ? 122 : 44;
    }
    function toggle(position) {
        if (opened) { close(); return; }
        if (paste.running || sendPaste.running || shell.captureActive || !position.address) return;
        const monitor = shell.fixture ? null : Hyprland.monitors.values.find(m => m.id === position.monitor);
        const output = Quickshell.screens.find(s => s.name === monitor?.name)
            || Quickshell.screens.find(s => position.x >= s.x && position.x < s.x + s.width
                && position.top >= s.y && position.top < s.y + s.height)
            || shell.focusedScreen;
        if (!output || !shell.mainScreen) return;

        const resume = screen === output && progress > 0;
        const pill = shell.pill.pillGeometry;
        const pillX = shell.mainScreen.x + pill.x - output.x;
        const pillY = shell.mainScreen.y + pill.y - output.y;
        const from = resume ? geometry : Qt.rect(clamp(pillX, -pill.width, output.width),
            clamp(pillY, -pill.height, output.height), pill.width, pill.height);
        const reveal = resume ? progress : 0;
        shell.panel = "";
        screen = output;
        location = position;
        error = "";
        entries = shell.fixture ? (shell.fixtureData.clipboard || []) : [];
        list.currentIndex = 0;
        list.positionViewAtBeginning();
        if (!shell.fixture) {
            loading = true;
            readHistory.running = true;
        }
        animate(from, reveal, true);
        list.forceActiveFocus();
        armFocus.restart();
    }
    function close() {
        if (!opened) return;
        wheel.stop();
        closingSelection = list.activeFocus ? list.currentIndex : -1;
        animate(geometry, progress, false);
        armFocus.stop();
        if (focusGrab) focusGrab.active = false;
    }
    function accept(index) {
        if (!opened || paste.running || clearHistory.running || index < 0 || index >= entries.length) return;
        const id = entries[index].id;
        const address = location.address;
        close();
        if (shell.fixture) {
            shell.fixtureEvent("clipboard-paste", {id: id, address: address});
            return;
        }
        // Give the layer one frame to release keyboard focus before inserting.
        paste.command = [shell.helper, "desktop", "clipboard-paste", id, address];
        sendPaste.restart();
    }
    function clear() {
        if (!opened || loading || clearHistory.running || entries.length === 0) return;
        if (shell.fixture) {
            entries = [];
            shell.fixtureData = Object.assign({}, shell.fixtureData, {clipboard: []});
            shell.fixtureEvent("clipboard-clear", {});
            list.forceActiveFocus();
        } else clearHistory.running = true;
    }

    Timer { id: sendPaste; interval: 34; onTriggered: paste.running = true }
    Timer {
        id: armFocus
        interval: 0
        onTriggered: {
            if (root.opened && root.focusGrab) root.focusGrab.active = true;
        }
    }
    Component { id: grabComponent; HyprlandFocusGrab {} }
    Component.onCompleted: {
        if (!shell.fixture && Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
            focusGrab = grabComponent.createObject(root, {windows: [root]});
            focusGrab.cleared.connect(() => { if (root.opened) root.close(); });
        }
    }
    Connections {
        target: root.shell
        function onPanelChanged() { if (root.shell.panel && root.opened) root.close(); }
        function onCaptureActiveChanged() { if (root.shell.captureActive && root.opened) root.close(); }
    }
    Connections {
        target: Hyprland
        enabled: !root.shell.fixture
        function onRawEvent(event) {
            if (root.opened && (event.name === "workspacev2"
                || (event.name === "activewindowv2" && event.data && "0x" + event.data !== root.location.address))) root.close();
        }
    }

    Process {
        id: readHistory
        command: [root.shell.helper, "desktop", "clipboard-list"]
        stdout: StdioCollector {
            id: historyOutput
            onStreamFinished: {
                if (!root.opened || !text) return;
                try { root.entries = JSON.parse(text); list.currentIndex = 0; }
                catch (_) { root.error = "Could not load clipboard history."; }
            }
        }
        onExited: code => {
            root.loading = false;
            if (code !== 0) root.error = "Could not load clipboard history.";
        }
    }
    Process {
        id: paste
        stderr: StdioCollector {
            onStreamFinished: { if (text.trim()) console.warn("Clipboard paste:", text.trim()); }
        }
    }
    Process {
        id: clearHistory
        command: [root.shell.helper, "desktop", "clipboard-clear"]
        onExited: code => {
            if (code === 0) root.entries = [];
            else root.error = "Could not clear clipboard history.";
            list.forceActiveFocus();
        }
    }

    // Measure the initial rows at their settled width before placing the popup.
    // The viewport size must not change as ListView recycles rows during scroll.
    Column {
        id: rowSizes
        width: Math.max(1, root.listWidth - 2 * root.entryGap)
        spacing: root.entryGap
        opacity: 0
        enabled: false
        Repeater {
            model: root.entries.slice(0, 11)
            delegate: Item {
                required property var modelData
                width: rowSizes.width
                height: root.rowHeight(modelData, measure.item?.implicitHeight ?? 44)
                Loader {
                    id: measure
                    width: rowSizes.width
                    active: modelData.kind === "html"
                    sourceComponent: ClipboardRichText { theme: root.theme; html: modelData.html }
                }
            }
        }
    }

    ClippingRectangle {
        id: body
        objectName: "clipboardHistory"
        color: "transparent"
        radius: 20
        clip: true
        x: root.blend(root.origin.x, root.destination.x)
        y: root.blend(root.origin.y, root.destination.y)
        width: root.blend(root.origin.width, root.destination.width)
        height: root.blend(root.origin.height, root.destination.height)
        opacity: Math.min(1, root.progress * 4)
        PillOverviewSurface {
            anchors.fill: parent
            radius: body.radius
            theme: root.theme
            panelGradient: theme.popupGradients.clipboard
        }
        ListView {
            id: list
            objectName: "clipboardEntries"
            anchors.fill: parent
            anchors.margins: root.entryGap
            anchors.bottomMargin: 0
            bottomMargin: root.entryGap
            opacity: root.opened ? root.clamp((root.progress - 0.42) * 2.5, 0, 1) : Math.min(1, root.progress * 2)
            enabled: root.opened && !clearHistory.running
            clip: true
            spacing: root.entryGap
            boundsBehavior: Flickable.StopAtBounds
            // A hovered edge row can be partially visible. Only the keyboard
            // should scroll the selected row into view.
            highlightFollowsCurrentItem: false
            activeFocusOnTab: true
            model: root.entries
            PillWheel { id: wheel; flickable: list; duration: 150 }
            onModelChanged: wheel.stop()
            function moveSelection(by) {
                if (!count) return;
                wheel.stop();
                currentIndex = root.clamp(currentIndex + by, 0, count - 1);
                positionViewAtIndex(currentIndex, ListView.Contain);
            }
            Keys.onUpPressed: moveSelection(-1)
            Keys.onDownPressed: moveSelection(1)
            Keys.onReturnPressed: root.accept(currentIndex)
            Keys.onEnterPressed: root.accept(currentIndex)
            Keys.onEscapePressed: root.close()
            KeyNavigation.tab: clearButton.enabled ? clearButton : list
            HoverHandler {
                parent: list
                enabled: list.enabled && root.progress >= 0.95
                property point lastPosition: Qt.point(-1, -1)
                onHoveredChanged: { if (!hovered) lastPosition = Qt.point(-1, -1); }
                onPointChanged: {
                    // Scrolling moves the content under a stationary pointer.
                    const position = point.scenePosition;
                    if (!hovered || (position.x === lastPosition.x && position.y === lastPosition.y)) return;
                    lastPosition = position;
                    const content = list.contentItem.mapFromItem(null, position);
                    const index = list.indexAt(content.x, content.y);
                    if (index < 0) return;
                    list.currentIndex = index;
                    if (!list.activeFocus) list.forceActiveFocus(Qt.MouseFocusReason);
                }
            }
            delegate: ClipboardRow {
                stillImage: root.isImage(modelData)
                width: list.width
                height: root.rowHeight(modelData, implicitHeight)
                theme: root.theme
                focusEmber: clipboardEmber
                helper: root.shell.helper
                fixture: root.shell.fixture
                previewVisible: root.opened && root.progress >= 0.95
                    && y + height > list.contentY && y < list.contentY + list.height
                selected: root.opened
                    ? ListView.isCurrentItem && list.activeFocus && (!root.shell.emberEnabled || root.progress >= 0.95)
                    : index === root.closingSelection
                onActivated: root.accept(index)
            }
        }
        Text {
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 22)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: root.error.length > 0 || list.count === 0
            opacity: list.opacity
            text: root.error || (root.loading ? "Loading…" : "Nothing copied yet")
            color: root.error ? root.theme.red : root.theme.secondary
            font: root.theme.textFont
        }
    }
    ShellButton {
        id: clearButton
        objectName: "clipboardFlush"
        z: 1
        x: root.fitsRight ? body.x + body.width + root.margin : body.x - width - root.margin
        y: body.y + 4
        width: root.buttonSize; height: width; radius: width / 2
        theme: root.theme
        emberSlot.ember: clipboardEmber
        hint: "Clear clipboard history"
        icon: "list-x"
        iconSize: 18
        visible: root.progress > 0.55
        enabled: root.opened && !root.loading && !clearHistory.running && root.entries.length > 0
        opacity: root.clamp((root.progress - 0.55) * 3, 0, 1) * (enabled ? 1 : 0.55)
        PillBackground { anchors.fill: parent; radius: parent.radius; theme: root.theme; z: -1 }
        Keys.onEscapePressed: root.close()
        KeyNavigation.tab: list
        onClicked: root.clear()
    }
    Ember {
        id: clipboardEmber
        anchors.fill: parent
        z: 2
        color: root.theme.focusColor
        target: !root.opened || root.progress < 0.95 || !root.shell.emberEnabled ? null
            : interactionTarget || (list.activeFocus ? list.currentItem?.emberSlot || null : null)
        active: !!target
    }
}
