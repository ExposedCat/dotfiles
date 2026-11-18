import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as Desktop
import "lib/fuzzy.js" as Fuzzy

ColumnLayout {
    id: root
    required property var theme
    property var applications: []
    property string filename: ""
    property string selectedId: ""
    property point pointerPosition: Qt.point(-1, -1)
    readonly property var results: Fuzzy.rank(applications.map(app => Object.assign({kind: "app"}, app)), search.text, {})
    signal accepted(string identity)
    spacing: 4
    function focusSearch() { search.forceActiveFocus(); }
    function activate() {
        pointerPosition = Qt.point(-1, -1);
        if (search.text) search.clear();
        else resetSelection();
        Qt.callLater(focusSearch);
    }
    function choose(index) {
        list.currentIndex = index;
        selectedId = index >= 0 && index < results.length ? results[index].id : "";
    }
    function resetSelection() {
        choose(results.length ? 0 : -1);
        list.positionViewAtBeginning();
    }
    function moveSelection(delta) {
        if (!results.length) return;
        choose(Math.max(0, Math.min(list.currentIndex + delta, results.length - 1)));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }
    function accept() { if (selectedId) accepted(selectedId); }
    onResultsChanged: Qt.callLater(resetSelection)
    TextField {
        id: search; objectName: "portalAppSearch"
        Layout.fillWidth: true; implicitHeight: 36; focus: true
        font: root.theme.textFont
        color: root.theme.text
        placeholderText: "Open with…"; placeholderTextColor: root.theme.secondary
        leftPadding: 50; rightPadding: 12; selectByMouse: true
        background: Item {
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 50; rightMargin: 12 }
                height: 2; radius: 1; color: root.theme.focusColor
                visible: search.activeFocus
            }
        }
        Desktop.ShellIcon { x: 13; y: Math.round((parent.height - height) / 2); name: "search"; width: 24; height: 24; opacity: 0.8 }
        onTextChanged: root.pointerPosition = Qt.point(-1, -1)
        Keys.onDownPressed: root.moveSelection(1)
        Keys.onUpPressed: root.moveSelection(-1)
        onAccepted: root.accept()
        Accessible.name: "Search applications"
        Accessible.description: root.filename
    }
    ListView {
        id: list; objectName: "portalApps"
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 2
        model: root.results; currentIndex: count ? 0 : -1
        boundsBehavior: Flickable.StopAtBounds
        Desktop.PillWheel { flickable: list }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Desktop.LauncherResult {
            id: row
            theme: root.theme; width: list.width
            selected: ListView.isCurrentItem
            onPointerMoved: (x, y) => {
                const p = mapToItem(root, x, y);
                if (root.pointerPosition.x >= 0 && (Math.abs(p.x - root.pointerPosition.x) > 0.5 || Math.abs(p.y - root.pointerPosition.y) > 0.5))
                    root.choose(index);
                root.pointerPosition = p;
            }
            onActivated: { root.choose(index); root.accept(); }
        }
        Text {
            anchors.centerIn: parent; width: parent.width - 20; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
            visible: list.count === 0; text: "No matches"
            color: root.theme.secondary; font: root.theme.textFont
        }
    }
}
