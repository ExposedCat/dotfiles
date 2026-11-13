import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "shell" as Desktop
import "portals"

Scope {
    id: root
    property var data: ({kind: "apps", apps: [], app: {name: "Application"}})
    property bool ready: false
    property bool submitting: false
    property bool details: false
    property real reveal: 0
    property string error: ""
    property string selected: ""
    property var selections: ({})
    property string tab: "screen"
    property bool remember: false
    property bool regionMode: false
    property var region: null
    readonly property string directory: Quickshell.env("DOTFILES_PORTAL_REQUEST") || ""
    readonly property bool fixture: !!data.fixture
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("portals/frontend.py").toString().replace(/^file:\/\//, ""))
    readonly property bool sharing: data.kind === "share"
    readonly property bool permission: data.kind === "access"
    readonly property var apps: (data.apps || []).filter(app => (app.name + " " + app.description).toLowerCase().includes(search.text.trim().toLowerCase()))
    readonly property var sources: tab === "screen" ? (data.outputs || []) : tab === "window" ? (data.windows || []) : (data.workspaces || [])
    readonly property int columns: tab === "screen" ? 2 : 3
    readonly property var chosenSource: sources.find(s => s.id === selected) || null
    readonly property bool canAccept: permission || (sharing ? !!chosenSource && (!regionMode || (!!region && regionPreview.hasPreview)) : apps.some(a => a.id === selected))
    function load() {
        try {
            data = JSON.parse(request.text());
            if (!ready) {
                remember = !!data.remember;
                const values = {};
                for (const choice of data.choices || []) values[choice.id] = choice.selected;
                selections = values;
                ready = true;
                opening.start();
                if (sharing) tabs.forceActiveFocus();
                else if (permission) cancel.forceActiveFocus();
                else search.forceActiveFocus();
            }
            if (!sharing && !permission && !(data.apps || []).some(a => a.id === selected)) selected = "";
        } catch (e) { error = "Could not load the request." }
    }
    function choose(identity) { selected = identity; region = null }
    function setTab(value) {
        if (tab === value) return;
        tab = value; selected = ""; region = null; regionMode = false;
        tabChange.restart();
    }
    function decide(code) {
        if (submitting || (code === 0 && !canAccept)) return;
        submitting = true;
        let response = {response: code};
        if (code === 0) {
            if (permission) response.choices = selections;
            else response.choice = selected;
            if (sharing) { response.remember = remember; if (regionMode) response.region = region }
        }
        writer.command = ["/usr/bin/python3", helper, "respond", directory, JSON.stringify(response)];
        opening.stop();
        closing.start();
    }
    NumberAnimation { id: opening; target: root; property: "reveal"; to: 1; duration: 150; easing.type: Easing.OutCubic }
    NumberAnimation { id: closing; target: root; property: "reveal"; to: 0; duration: 90; easing.type: Easing.InCubic; onFinished: writer.running = true }
    FileView { id: request; path: root.directory + "/request.json"; watchChanges: true; blockLoading: true; onLoaded: root.load(); onFileChanged: reload() }
    Process {
        id: writer
        onExited: (code, status) => { if (code === 0) Qt.quit(); else { root.submitting = false; root.error = "Could not send the response."; opening.start() } }
    }
    Desktop.ShellTheme { id: portalTheme }
    FloatingWindow {
        id: window
        title: "Desktop portal: " + (root.sharing ? "Screen sharing" : root.permission ? "Permission" : "Open With")
        implicitWidth: root.sharing ? 680 : 440
        implicitHeight: root.sharing ? (root.regionMode ? 470 : Math.min(520, Math.max(310, 138 + Math.ceil(root.sources.length / root.columns) * 172)))
                        : root.permission ? Math.min(620, permissionContent.implicitHeight + 108) : Math.min(440, 140 + Math.max(1, (root.data.apps || []).length) * 50)
        minimumSize: Qt.size(implicitWidth, implicitHeight)
        maximumSize: minimumSize
        color: "transparent"
        visible: root.ready
        onClosed: root.decide(1)
        Shortcut { sequence: "Escape"; onActivated: root.decide(1) }
        Rectangle {
            id: surface
            anchors.fill: parent
            color: portalTheme.background
            radius: 16
            border.width: 1; border.color: "#292929"
            opacity: root.reveal
            scale: 0.97 + root.reveal * 0.03
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 18; spacing: 14
                RowLayout {
                    visible: root.sharing; Layout.fillWidth: true; spacing: 12
                    Item {
                        id: tabs
                        Layout.fillWidth: true; implicitHeight: 36
                        readonly property int index: root.tab === "screen" ? 0 : root.tab === "window" ? 1 : 2
                        Keys.onRightPressed: root.setTab(["screen", "window", "workspace"][Math.min(2, index + 1)])
                        Keys.onLeftPressed: root.setTab(["screen", "window", "workspace"][Math.max(0, index - 1)])
                        Rectangle { anchors.fill: parent; radius: 9; color: portalTheme.surface }
                        Rectangle {
                            x: 3 + tabs.index * (tabs.width - 6) / 3; y: 3
                            width: (tabs.width - 6) / 3; height: tabs.height - 6
                            radius: 7; color: "#353535"
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        Repeater {
                            model: [{id: "screen", name: "Monitors"}, {id: "window", name: "Windows"}, {id: "workspace", name: "Workspaces"}]
                            Item {
                                required property var modelData
                                required property int index
                                x: 3 + index * (tabs.width - 6) / 3; width: (tabs.width - 6) / 3; height: tabs.height
                                activeFocusOnTab: true
                                Accessible.role: Accessible.PageTab; Accessible.name: modelData.name; Accessible.selected: root.tab === modelData.id
                                Keys.onReturnPressed: root.setTab(modelData.id)
                                Keys.onSpacePressed: root.setTab(modelData.id)
                                Text { anchors.centerIn: parent; text: modelData.name; color: root.tab === modelData.id ? portalTheme.text : "#999999"; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize; Behavior on color { ColorAnimation { duration: 120 } } }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { tabs.forceActiveFocus(); root.setTab(parent.modelData.id); } }
                            }
                        }
                    }
                    Desktop.ShellButton { id: shareClose; theme: portalTheme; icon: "x"; hint: "Cancel sharing"; implicitWidth: 30; implicitHeight: 30; onClicked: root.decide(1) }
                }
                TextField {
                    id: search
                    visible: !root.permission && !root.sharing
                    Layout.fillWidth: true; implicitHeight: 40
                    leftPadding: 12; rightPadding: 12
                    font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize
                    color: portalTheme.text; placeholderText: "Open with…"; placeholderTextColor: "#999999"; selectByMouse: true
                    Accessible.name: "Search applications"; Accessible.description: root.data.filename || ""
                    background: Rectangle { radius: 9; color: portalTheme.surface; border.width: 1; border.color: search.activeFocus ? "#555555" : "transparent"; Behavior on border.color { ColorAnimation { duration: 120 } } }
                    onTextChanged: { if (!root.apps.some(a => a.id === root.selected)) root.selected = "" }
                    Keys.onDownPressed: {
                        const i = root.apps.findIndex(a => a.id === root.selected);
                        if (root.apps.length) { const next = Math.min(root.apps.length - 1, i + 1); root.selected = root.apps[next].id; appList.positionViewAtIndex(next, ListView.Contain) }
                    }
                    Keys.onUpPressed: {
                        const i = root.apps.findIndex(a => a.id === root.selected);
                        if (root.apps.length) { const next = Math.max(0, i - 1); root.selected = root.apps[next].id; appList.positionViewAtIndex(next, ListView.Contain) }
                    }
                    onAccepted: root.decide(0)
                }
                ListView {
                    id: appList
                    visible: !root.permission && !root.sharing
                    Layout.fillWidth: true; Layout.fillHeight: true
                    model: root.apps; spacing: 2; clip: true; boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        id: appRow
                        required property var modelData
                        readonly property bool chosen: root.selected === modelData.id
                        width: appList.width; height: 48; radius: 8
                        color: chosen ? "#262626" : appPointer.containsMouse ? portalTheme.surface : "transparent"
                        scale: appPointer.pressed ? 0.985 : 1
                        Behavior on color { ColorAnimation { duration: 110 } }
                        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                        activeFocusOnTab: true
                        Accessible.role: Accessible.RadioButton; Accessible.name: modelData.name; Accessible.checked: chosen
                        Keys.onSpacePressed: root.selected = modelData.id
                        Keys.onReturnPressed: { root.selected = modelData.id; root.decide(0) }
                        Rectangle { x: 0; anchors.verticalCenter: parent.verticalCenter; width: 3; height: 20; radius: 1.5; color: portalTheme.accent; opacity: appRow.chosen || appRow.activeFocus ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 100 } } }
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 12
                            Item {
                                Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                Image { id: appIcon; anchors.fill: parent; sourceSize: Qt.size(26, 26); source: appRow.modelData.icon ? (appRow.modelData.icon.startsWith("/") ? "file://" + appRow.modelData.icon : Quickshell.iconPath(appRow.modelData.icon, true)) : "" }
                                Text { anchors.centerIn: parent; visible: appIcon.status !== Image.Ready; text: appRow.modelData.name.charAt(0); color: portalTheme.secondary; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize }
                            }
                            Text { Layout.fillWidth: true; text: appRow.modelData.name; textFormat: Text.PlainText; color: portalTheme.text; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize; elide: Text.ElideRight }
                        }
                        MouseArea { id: appPointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selected = appRow.modelData.id; onDoubleClicked: { root.selected = appRow.modelData.id; root.decide(0) } }
                    }
                    Text { anchors.centerIn: parent; visible: appList.count === 0; text: "No applications"; color: portalTheme.secondary; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize }
                }
                ScrollView {
                    visible: root.permission; Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth; clip: true
                    ColumnLayout {
                        id: permissionContent
                        width: parent.width; spacing: 12
                        Text { Layout.fillWidth: true; text: root.data.app ? root.data.app.name : "Application"; textFormat: Text.PlainText; color: "#999999"; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: root.data.title || "Allow access?"; textFormat: Text.PlainText; color: portalTheme.text; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize; wrapMode: Text.Wrap }
                        Text { Layout.fillWidth: true; visible: root.details; text: [root.data.subtitle || "", root.data.body || ""].filter(s => s.length > 0).join("\n\n"); textFormat: Text.PlainText; color: portalTheme.secondary; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize; wrapMode: Text.Wrap }
                        Repeater {
                            model: root.data.choices || []
                            RowLayout {
                                id: optionRow
                                required property var modelData
                                Layout.fillWidth: true; spacing: 12
                                PortalCheckBox {
                                    theme: portalTheme; visible: optionRow.modelData.values.length === 0; Layout.fillWidth: true
                                    text: optionRow.modelData.name; checked: root.selections[optionRow.modelData.id] === "true"
                                    onToggled: { const values = Object.assign({}, root.selections); values[optionRow.modelData.id] = checked ? "true" : "false"; root.selections = values }
                                }
                                Text { visible: optionRow.modelData.values.length > 0; Layout.fillWidth: true; text: optionRow.modelData.name; textFormat: Text.PlainText; color: portalTheme.text; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize; wrapMode: Text.Wrap }
                                ComboBox {
                                    visible: optionRow.modelData.values.length > 0; Layout.maximumWidth: 180
                                    model: optionRow.modelData.values; textRole: "name"; valueRole: "id"
                                    currentIndex: model.findIndex(v => v.id === root.selections[optionRow.modelData.id])
                                    Accessible.name: optionRow.modelData.name
                                    font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize
                                    onActivated: { const values = Object.assign({}, root.selections); values[optionRow.modelData.id] = currentValue; root.selections = values }
                                    palette { button: portalTheme.surface; buttonText: portalTheme.text; window: portalTheme.surface; text: portalTheme.text; highlight: portalTheme.accent; highlightedText: "black"; base: portalTheme.surface }
                                }
                            }
                        }
                    }
                }
                GridView {
                    id: sourceGrid
                    property real transition: 1
                    visible: root.sharing; Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; model: root.sources; cellWidth: Math.floor(width / root.columns); cellHeight: 172
                    opacity: transition; transform: Translate { y: (1 - sourceGrid.transition) * 6 }
                    boundsBehavior: Flickable.StopAtBounds; ScrollBar.vertical: ScrollBar {}
                    NumberAnimation { id: tabChange; target: sourceGrid; property: "transition"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }
                    delegate: Item {
                        id: sourceCard
                        required property var modelData
                        readonly property bool chosen: root.selected === modelData.id
                        width: sourceGrid.cellWidth - 8; height: 164
                        // GridView places delegates flush against its clip edge.
                        // Reserve room for the hover scale on all four sides.
                        transform: Translate { x: 4; y: 4 }
                        scale: sourcePointer.pressed ? 0.975 : sourcePointer.containsMouse ? 1.012 : 1
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        activeFocusOnTab: true
                        Accessible.role: Accessible.RadioButton; Accessible.name: modelData.name + ", " + modelData.subtitle; Accessible.checked: chosen
                        Keys.onSpacePressed: root.choose(modelData.id)
                        Keys.onReturnPressed: root.choose(modelData.id)
                        SourcePreview { id: sourcePreview; anchors { top: parent.top; left: parent.left; right: parent.right } height: 132; sourceData: sourceCard.modelData; theme: portalTheme; fixture: root.fixture }
                        Rectangle {
                            anchors.fill: sourcePreview; radius: 11; color: "transparent"
                            border.width: sourceCard.chosen || sourceCard.activeFocus ? 2 : 1
                            border.color: sourceCard.chosen || sourceCard.activeFocus ? portalTheme.accent : sourcePointer.containsMouse ? "#555555" : "#282828"
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                        Text { anchors { left: parent.left; right: parent.right; top: sourcePreview.bottom; topMargin: 8 } text: sourceCard.modelData.name; textFormat: Text.PlainText; color: sourceCard.chosen ? portalTheme.text : portalTheme.secondary; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize; elide: Text.ElideRight }
                        MouseArea { id: sourcePointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { sourceCard.forceActiveFocus(); root.choose(sourceCard.modelData.id); } }
                    }
                    Text { anchors.centerIn: parent; visible: sourceGrid.count === 0; text: "No sources"; color: portalTheme.secondary; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize }
                }
                Rectangle {
                    visible: root.sharing && root.regionMode && !!root.chosenSource
                    Layout.fillWidth: true; Layout.preferredHeight: 140; color: portalTheme.surface; radius: 10; clip: true
                    SourcePreview { id: regionPreview; anchors.centerIn: parent; width: Math.min(parent.width, parent.height * ((root.chosenSource || {}).width || 1) / ((root.chosenSource || {}).height || 1)); height: parent.height; sourceData: root.chosenSource || {}; theme: portalTheme; fixture: root.fixture }
                    Rectangle {
                        visible: !!root.region
                        x: regionPreview.x + (root.region ? root.region[0] / root.chosenSource.width * regionPreview.width : 0)
                        y: root.region ? root.region[1] / root.chosenSource.height * regionPreview.height : 0
                        width: root.region ? root.region[2] / root.chosenSource.width * regionPreview.width : 0
                        height: root.region ? root.region[3] / root.chosenSource.height * regionPreview.height : 0
                        color: "#3389b4fa"; border.color: portalTheme.accent; border.width: 2
                    }
                    MouseArea {
                        x: regionPreview.x; y: 0; width: regionPreview.width; height: regionPreview.height; cursorShape: Qt.CrossCursor
                        property real startX: 0; property real startY: 0
                        function updateRegion(mouse) {
                            const source = root.chosenSource;
                            if (!source) return;
                            const endX = Math.max(0, Math.min(width, mouse.x)), endY = Math.max(0, Math.min(height, mouse.y));
                            const x = Math.floor(Math.min(startX, endX) / width * source.width), y = Math.floor(Math.min(startY, endY) / height * source.height);
                            const right = Math.floor(Math.max(startX, endX) / width * source.width), bottom = Math.floor(Math.max(startY, endY) / height * source.height);
                            root.region = right > x && bottom > y ? [x, y, right - x, bottom - y] : null;
                        }
                        onPressed: mouse => { startX = mouse.x; startY = mouse.y; root.region = null }
                        onPositionChanged: mouse => { if (pressed) updateRegion(mouse) }
                        onReleased: mouse => updateRegion(mouse)
                    }
                }
                Text { visible: root.error.length > 0; text: root.error; Layout.fillWidth: true; wrapMode: Text.Wrap; color: portalTheme.red; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    PortalCheckBox { visible: root.sharing; theme: portalTheme; text: "Remember"; checked: root.remember; onToggled: root.remember = checked }
                    PortalCheckBox { visible: root.sharing && root.tab === "screen" && !!root.chosenSource; theme: portalTheme; text: "Region"; checked: root.regionMode; onToggled: { root.regionMode = checked; root.region = null } }
                    Desktop.ShellButton { visible: root.permission && !!(root.data.body || root.data.subtitle); theme: portalTheme; text: "…"; hint: "Request details"; selected: root.details; implicitWidth: 32; Accessible.name: "Request details"; onClicked: root.details = !root.details }
                    Item { Layout.fillWidth: true }
                    PortalButton { id: cancel; visible: !root.sharing; theme: portalTheme; text: root.permission ? root.data.denyLabel || "Deny" : "Cancel"; enabled: !root.submitting; onClicked: root.decide(1) }
                    PortalButton { theme: portalTheme; text: root.sharing ? "Share" : root.permission ? root.data.grantLabel || "Allow" : "Open"; primary: true; enabled: root.canAccept && !root.submitting; onClicked: root.decide(0) }
                }
            }
        }
    }
}
