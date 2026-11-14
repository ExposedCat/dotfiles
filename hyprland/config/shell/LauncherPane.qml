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
    spacing: 8
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
        implicitHeight: 36
        focus: true
        font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize
        color: root.theme.text
        placeholderText: "Search apps"
        placeholderTextColor: root.theme.secondary
        leftPadding: 32; rightPadding: 10
        selectByMouse: true
        cursorVisible: !root.shell.emberEnabled
        background: Item {}
        ShellIcon { x: 1; y: Math.round((parent.height - height) / 2); name: "search"; width: 21; height: 21; opacity: 0.8 }
        EmberSlot { id: caretSlot; shell: root.shell; x: search.cursorRectangle.x; y: search.cursorRectangle.y; width: 3; height: search.cursorRectangle.height || 19; shapeRadius: 1.5; caret: true }
        onTextChanged: { root.copied = false; Qt.callLater(() => list.currentIndex = list.count ? 0 : -1); }
        Keys.onDownPressed: { list.currentIndex = Math.min(list.currentIndex + 1, list.count - 1); list.positionViewAtIndex(list.currentIndex, ListView.Contain); }
        Keys.onUpPressed: { list.currentIndex = Math.max(list.currentIndex - 1, 0); list.positionViewAtIndex(list.currentIndex, ListView.Contain); }
        onAccepted: root.launch()
        Accessible.name: "Search applications or calculate"
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.alpha(root.theme.border, 0.35) }
    ShellButton {
        Layout.fillWidth: true; implicitHeight: 40
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
        clip: true; spacing: 2
        model: root.matches
        currentIndex: count ? 0 : -1
        boundsBehavior: Flickable.StopAtBounds
        PillWheel { flickable: list }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Rectangle {
            id: appRow
            required property var modelData
            required property int index
            width: list.width; height: 44; radius: 10
            color: ListView.isCurrentItem ? Qt.alpha(root.theme.hover, 0.58) : "transparent"
            border.width: ListView.isCurrentItem ? 1 : 0
            border.color: Qt.alpha(root.theme.border, 0.22)
            RowLayout {
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                spacing: 10
                Item {
                    Layout.preferredWidth: 21; Layout.preferredHeight: 21
                    Image {
                        id: appIcon
                        anchors.fill: parent
                        source: appRow.modelData.icon ? (appRow.modelData.icon.startsWith("/") ? "file://" + appRow.modelData.icon : Quickshell.iconPath(appRow.modelData.icon, true)) : ""
                        visible: status === Image.Ready
                        sourceSize.width: 32; sourceSize.height: 32; fillMode: Image.PreserveAspectFit
                    }
                    ShellIcon { anchors.centerIn: parent; name: "grid-2x2"; width: 21; height: 21; visible: !appIcon.visible; opacity: 0.8 }
                }
                Text { Layout.fillWidth: true; text: appRow.modelData.name; textFormat: Text.PlainText; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; color: root.theme.text; elide: Text.ElideRight }
                Text {
                    Layout.preferredWidth: Math.min(implicitWidth, list.width * 0.44)
                    text: appRow.modelData.description || ""; textFormat: Text.PlainText
                    font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize; color: root.theme.secondary
                    horizontalAlignment: Text.AlignRight; elide: Text.ElideRight
                }
                Text { Layout.preferredWidth: 18; text: "↵"; color: "#cc7855"; font.pixelSize: root.theme.bodySize; opacity: appRow.ListView.isCurrentItem ? 1 : 0 }
            }
            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onEntered: list.currentIndex = appRow.index; onClicked: { list.currentIndex = appRow.index; root.launch(); } }
            Accessible.role: Accessible.Button
            Accessible.name: modelData.name
            Accessible.onPressAction: { list.currentIndex = index; root.launch(); }
        }
        Text { anchors.centerIn: parent; visible: list.count === 0 && !root.calculation.ok; text: root.loading ? "Loading applications…" : root.error || "No applications found"; color: root.error ? root.theme.red : root.theme.secondary; font.family: root.theme.fontFamily; font.pixelSize: root.theme.bodySize }
    }
}
