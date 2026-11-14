import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "lib/fuzzy.js" as Fuzzy
import "lib/calc.js" as Calc

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    Applications { id: localIndex; shell: root.shell }
    readonly property var indexStore: shell.applications || localIndex
    readonly property var installedApps: indexStore.apps
    readonly property var apps: indexStore.apps
    readonly property string error: indexStore.error
    property bool launching: false
    property bool copied: false
    readonly property bool loading: indexStore.loading
    readonly property var matches: Fuzzy.rank(apps, search.text, indexStore.usage)
    readonly property var calculation: Calc.evaluate(search.text.slice(0, 256))
    readonly property Item emberTarget: caretSlot
    spacing: 12
    function launch() {
        if (calculation.ok) { copyResult(); return; }
        if (launching || list.currentIndex < 0 || list.currentIndex >= matches.length) return;
        launching = true;
        const app = matches[list.currentIndex];
        indexStore.record(app.id);
        if (shell.fixture) shell.fixtureEvent("app-launch", {id: app.id});
        else Quickshell.execDetached(["/usr/bin/python3", shell.helper, "app-launch", app.id]);
        shell.panel = "";
    }
    function copyResult() {
        if (!calculation.ok) return;
        if (shell.fixture) shell.fixtureEvent("calculator-copy", {value: calculation.display});
        else Quickshell.execDetached(["/usr/bin/python3", shell.helper, "copy-text", "--", calculation.display]);
        copied = true;
    }
    function focusSearch() { search.forceActiveFocus(); }
    function activate() { launching = false; indexStore.refresh(); Qt.callLater(focusSearch); }
    Component.onCompleted: activate()
    TextField {
        id: search
        objectName: "pillSearch"
        Layout.fillWidth: true
        implicitHeight: 48
        focus: true
        font.family: root.theme.fontFamily; font.weight: root.theme.fontWeight; font.pixelSize: root.theme.bodySize
        color: root.theme.text
        placeholderText: "Search apps or calculate…"
        placeholderTextColor: root.theme.secondary
        leftPadding: 16; rightPadding: 16
        selectByMouse: true
        cursorVisible: !root.shell.emberEnabled
        EmberSlot { id: caretSlot; shell: root.shell; x: search.cursorRectangle.x; y: search.cursorRectangle.y; width: 3; height: search.cursorRectangle.height || 19; shapeRadius: 1.5; caret: true }
        background: Rectangle { color: root.theme.surface; radius: 24; border.width: 1; border.color: search.activeFocus ? root.theme.accent : root.theme.border }
        onTextChanged: { list.currentIndex = list.count ? 0 : -1; root.copied = false; }
        Keys.onDownPressed: { list.currentIndex = Math.min(list.currentIndex + 1, list.count - 1); list.positionViewAtIndex(list.currentIndex, ListView.Contain); }
        Keys.onUpPressed: { list.currentIndex = Math.max(list.currentIndex - 1, 0); list.positionViewAtIndex(list.currentIndex, ListView.Contain); }
        onAccepted: root.launch()
        Accessible.name: "Search applications"
    }
    ShellButton {
        Layout.fillWidth: true; implicitHeight: 48
        visible: root.calculation.ok
        theme: root.theme
        text: "= " + root.calculation.display + (root.copied ? "   Copied" : "   ↵ Copy")
        hint: "Copy calculation result"
        onClicked: root.copyResult()
    }
    ListView {
        id: list
        objectName: "pillApps"
        Layout.fillWidth: true; Layout.fillHeight: true
        clip: true; spacing: 4
        model: root.matches
        currentIndex: count ? 0 : -1
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            required property var modelData
            required property int index
            width: list.width; height: 64; radius: 18
            color: ListView.isCurrentItem ? root.theme.hover : mouse.containsMouse ? root.theme.surface : "transparent"
            RowLayout {
                anchors.fill: parent; anchors.margins: 12; spacing: 12
                Image {
                    Layout.preferredWidth: 30; Layout.preferredHeight: 30
                    source: modelData.icon ? (modelData.icon.startsWith("/") ? "file://" + modelData.icon : Quickshell.iconPath(modelData.icon, true)) : ""
                    opacity: status === Image.Ready ? 1 : 0
                    sourceSize.width: 30; sourceSize.height: 30; fillMode: Image.PreserveAspectFit
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text { Layout.fillWidth: true; text: modelData.name; textFormat: Text.PlainText; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; color: root.theme.text; elide: Text.ElideRight }
                    Text { Layout.fillWidth: true; text: modelData.description || ""; textFormat: Text.PlainText; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; color: root.theme.secondary; elide: Text.ElideRight; visible: text.length > 0 }
                }
            }
            MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { list.currentIndex = index; root.launch(); } }
            Accessible.role: Accessible.Button
            Accessible.name: modelData.name
            Accessible.onPressAction: { list.currentIndex = index; root.launch(); }
        }
        Text { anchors.centerIn: parent; visible: list.count === 0; text: root.loading ? "Loading applications…" : root.error || "No applications found"; color: root.error ? root.theme.red : root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize }
    }
}
