import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    required property var theme
    property Item sharedEmber: null
    readonly property Item controlEmber: sharedEmber || dialogEmber
    readonly property Item emberTarget: sharing ? tabs.selectedSlot : permission ? null : appPicker.emberTarget
    property var requestData: ({kind: "apps", apps: []})
    property bool submitting: false
    property string error: ""
    readonly property string shownError: error || requestData.error || ""
    property string selected: ""
    property var selections: ({})
    property string tab: "screen"
    property bool remember: false
    readonly property bool fixture: !!requestData.fixture
    readonly property bool sharing: requestData.kind === "share"
    readonly property bool permission: requestData.kind === "access"
    readonly property string permissionHeading: permissionTitle(requestData)
    readonly property string permissionDescription: [requestData.subtitle || "", requestData.body || ""].filter(text => text.length > 0).join("\n\n")
    readonly property var permissionRememberChoice: (requestData.choices || []).find(choice => choice.id === "remember" && choice.values.length === 0) || null
    readonly property var results: appPicker.results
    readonly property var sources: tab === "screen" ? (requestData.outputs || []) : tab === "window" ? (requestData.windows || []) : (requestData.workspaces || [])
    readonly property int columns: tab === "screen" ? 2 : 3
    readonly property var chosenSource: sources.find(s => s.id === selected) || null
    readonly property bool canAccept: permission || (sharing ? !!chosenSource : results.some(a => a.id === selected))
    readonly property bool canSelectRegion: sharing && tab === "screen" && !!chosenSource
    readonly property real desiredWidth: sharing ? 680 : permission ? 440 : 560
    readonly property real desiredHeight: sharing ? Math.min(700, Math.max(402, 198 + Math.ceil(sources.length / columns) * 204)) + (selectedSourceName.visible ? Math.max(0, selectedSourceName.implicitHeight - 22) : 0) + (errorMessage.visible ? errorMessage.implicitHeight + 14 : 0)
                        : permission ? Math.min(620, permissionContent.implicitHeight + 108) : 428
    signal responded(var response)
    enabled: !submitting
    // AccessDialog supplies free text, not a microphone/camera resource field.
    // Rewrite only this simple question; preserve all other supplied wording.
    function permissionTitle(request) {
        const title = (request.title || "Allow access?").trim();
        const app = request.app?.name || request.app?.id || "";
        if (!app || title.startsWith(app + ":") || title.startsWith(app + " ")) return title;
        const access = /^Allow (.+) access\?$/i.exec(title);
        if (access) {
            if (access[1].toLowerCase().startsWith(app.toLowerCase() + " ")) return title;
            return "Allow " + app + " " + access[1] + " access?";
        }
        if (/^Allow access\?$/i.test(title)) return "Allow " + app + " access?";
        return app + ": " + title;
    }
    function focusSearch() {
        if (sharing) tabs.forceActiveFocus();
        else if (permission) cancel.forceActiveFocus();
        else appPicker.focusSearch();
    }
    function activate() {
        error = ""; selected = ""; tab = "screen";
        remember = !!requestData.remember;
        const values = {};
        for (const choice of requestData.choices || []) values[choice.id] = choice.selected;
        selections = values;
        appPicker.activate();
        if (sharing) selected = requestData.initialChoice || "";
        Qt.callLater(focusSearch);
    }
    function choose(identity) { selected = identity }
    function chooseApp(index) { appPicker.choose(index); }
    function accept() { decide(0); }
    function setTab(value) {
        if (tab === value) return;
        tab = value; selected = "";
        tabChange.restart();
    }
    function decide(code, selectRegion = false) {
        if (submitting || (code === 0 && !(selectRegion ? canSelectRegion : canAccept))) return;
        const response = {response: code};
        if (code === 0) {
            if (permission) response.choices = selections;
            else response.choice = selected;
            if (sharing) { response.remember = remember; if (selectRegion) response.selectRegion = true }
        }
        responded(response);
    }
    // Reuse the same theme binding throughout the standalone and pill views.
    readonly property var portalTheme: theme

    ColumnLayout {
        anchors.fill: parent
        spacing: root.sharing || root.permission ? 14 : 4
        RowLayout {
            visible: root.sharing; Layout.fillWidth: true; spacing: 12
            Item {
                id: tabs
                objectName: "shareTabs"
                Layout.fillWidth: true; implicitHeight: 42
                readonly property var options: [
                    {id: "screen", name: "Monitors"},
                    {id: "window", name: "Windows"},
                    {id: "workspace", name: "Workspaces"}
                ]
                readonly property int index: options.findIndex(option => option.id === root.tab)
                readonly property Item selectedSlot: tabRow.children.find(control => control.chosen)?.emberSlot || null
                activeFocusOnTab: true
                Accessible.role: Accessible.PageTabList
                Accessible.name: "Sharing sources"
                Keys.onRightPressed: root.setTab(options[Math.min(options.length - 1, index + 1)].id)
                Keys.onLeftPressed: root.setTab(options[Math.max(0, index - 1)].id)
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: portalTheme.overviewRim
                }
                RowLayout {
                    id: tabRow
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: Math.min(implicitWidth, tabs.width)
                    spacing: tabs.width < 340 ? 6 : 18
                    Repeater {
                        model: tabs.options
                        Item {
                            id: tabControl
                            required property var modelData
                            property alias emberSlot: tabSlot
                            readonly property bool chosen: root.tab === modelData.id
                            readonly property color ink: chosen || tabHover.hovered ? portalTheme.overviewInk : portalTheme.overviewSecondary
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.fillHeight: true
                            implicitWidth: tabLabel.implicitWidth + 20
                            Accessible.role: Accessible.PageTab
                            Accessible.name: modelData.name
                            Accessible.selected: chosen
                            Accessible.onPressAction: root.setTab(modelData.id)
                            Text {
                                id: tabLabel
                                anchors { centerIn: parent; verticalCenterOffset: -2 }
                                width: Math.min(implicitWidth, tabControl.width)
                                text: tabControl.modelData.name
                                elide: Text.ElideRight
                                font: portalTheme.textFont
                                color: tabControl.ink
                            }
                            Rectangle {
                                anchors.fill: tabSlot
                                radius: tabSlot.shapeRadius
                                color: portalTheme.overviewAccent
                                visible: tabControl.chosen && !tabSlot.occupied
                            }
                            EmberSlot {
                                id: tabSlot
                                shell: null; ember: root.controlEmber
                                anchors { left: tabLabel.left; right: tabLabel.right; bottom: parent.bottom }
                                height: 3; shapeRadius: 1.5
                            }
                            HoverHandler { id: tabHover }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { tabs.forceActiveFocus(); root.setTab(tabControl.modelData.id); } }
                        }
                    }
                }
            }
            ShellButton { id: shareClose; theme: portalTheme; icon: "x"; hint: "Cancel sharing"; implicitWidth: 30; implicitHeight: 30; onClicked: root.decide(1) }
        }
        PortalApps {
            id: appPicker
            visible: !root.permission && !root.sharing
            Layout.fillWidth: true; Layout.fillHeight: true
            theme: portalTheme; applications: root.requestData.apps || []; filename: root.requestData.filename || ""
            focusEmber: root.controlEmber
            onSelectedIdChanged: root.selected = selectedId
            onAccepted: identity => { root.selected = identity; root.decide(0) }
        }
        ScrollView {
            visible: root.permission; Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth; clip: true
            ColumnLayout {
                id: permissionContent
                width: parent.width; spacing: 12
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    ShellIcon { name: "shield-check"; Layout.preferredWidth: 26; Layout.preferredHeight: 26; Layout.alignment: Qt.AlignTop }
                    Text { Layout.fillWidth: true; objectName: "permissionHeading"; text: root.permissionHeading; textFormat: Text.PlainText; color: portalTheme.text; font: portalTheme.textFont; wrapMode: Text.Wrap }
                }
                Text { objectName: "permissionDescription"; Layout.fillWidth: true; visible: text.length > 0; text: root.permissionDescription; textFormat: Text.PlainText; color: portalTheme.secondary; font: portalTheme.textFont; wrapMode: Text.Wrap }
                Repeater {
                    model: (root.requestData.choices || []).filter(choice => choice.id !== root.permissionRememberChoice?.id)
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
                        PillComboBox {
                            visible: optionRow.modelData.values.length > 0; Layout.maximumWidth: 180
                            theme: portalTheme
                            model: optionRow.modelData.values; textRole: "name"; valueRole: "id"
                            currentIndex: model.findIndex(v => v.id === root.selections[optionRow.modelData.id])
                            Accessible.name: optionRow.modelData.name
                            onActivated: { const values = Object.assign({}, root.selections); values[optionRow.modelData.id] = currentValue; root.selections = values }
                        }
                    }
                }
            }
        }
        GridView {
            id: sourceGrid
            objectName: "shareSources"
            property real transition: 1
            visible: root.sharing; Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; model: root.sources; cellWidth: Math.floor(width / root.columns); cellHeight: 204
            opacity: transition; transform: Translate { y: (1 - sourceGrid.transition) * 6 }
            boundsBehavior: Flickable.StopAtBounds; ScrollBar.vertical: ScrollBar {}
            NumberAnimation { id: tabChange; target: sourceGrid; property: "transition"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }
            delegate: Item {
                id: sourceCard
                required property var modelData
                readonly property bool chosen: root.selected === modelData.id
                width: sourceGrid.cellWidth - 8; height: sourceGrid.cellHeight - 8
                // GridView places delegates flush against its clip edge.
                // Reserve room for the hover scale on all four sides.
                transform: Translate { x: 4; y: 4 }
                scale: sourcePointer.pressed ? 0.975 : 1
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                activeFocusOnTab: true
                Accessible.role: Accessible.RadioButton; Accessible.name: modelData.name + ", " + modelData.subtitle; Accessible.checked: chosen
                Keys.onSpacePressed: root.choose(modelData.id)
                Keys.onReturnPressed: root.choose(modelData.id)
                SourcePreview { id: sourcePreview; anchors { top: parent.top; left: parent.left; right: parent.right } height: 132; sourceData: sourceCard.modelData; theme: portalTheme; fixture: root.fixture }
                Rectangle {
                    anchors.fill: sourcePreview; radius: 11; color: "transparent"
                    border.width: sourceCard.activeFocus ? 1 : 0
                    border.color: portalTheme.focusColor
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                }
                Rectangle { visible: sourceCard.chosen; x: 0; y: sourcePreview.height + 4; width: parent.width; height: sourceName.height + 8; radius: 10; color: "#70cc7855" }
                Text { id: sourceName; objectName: "shareSourceName"; anchors { left: parent.left; right: parent.right; top: sourcePreview.bottom; leftMargin: 8; rightMargin: 8; topMargin: 8 } wrapMode: Text.Wrap; maximumLineCount: 2; text: sourceCard.modelData.name; textFormat: Text.PlainText; color: sourceCard.chosen ? portalTheme.text : portalTheme.secondary; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize; elide: Text.ElideRight }
                MouseArea { id: sourcePointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { sourceCard.forceActiveFocus(); root.choose(sourceCard.modelData.id); } }
            }
            Text { anchors.centerIn: parent; visible: sourceGrid.count === 0; text: "No sources"; color: portalTheme.secondary; font.family: portalTheme.fontFamily; font.weight: portalTheme.fontWeight; font.pixelSize: portalTheme.bodySize }
        }
        Text { id: selectedSourceName; objectName: "shareSelectedName"; visible: root.sharing && !!root.chosenSource && root.chosenSource.name.length > 36; Layout.fillWidth: true; text: root.chosenSource ? root.chosenSource.name : ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; font: portalTheme.textFont; color: portalTheme.text }
        Text { id: errorMessage; visible: root.shownError.length > 0; text: root.shownError; textFormat: Text.PlainText; Layout.fillWidth: true; wrapMode: Text.Wrap; color: portalTheme.red; font: portalTheme.textFont }
        RowLayout {
            visible: root.sharing || root.permission
            Layout.fillWidth: true; spacing: 8
            PortalCheckBox {
                objectName: "portalRemember"
                visible: root.sharing || (root.permission && !!root.permissionRememberChoice)
                theme: portalTheme; text: "Remember"
                checked: root.permission && root.permissionRememberChoice ? root.selections[root.permissionRememberChoice.id] === "true" : root.remember
                onToggled: {
                    if (root.permission && root.permissionRememberChoice) {
                        const values = Object.assign({}, root.selections);
                        values[root.permissionRememberChoice.id] = checked ? "true" : "false";
                        root.selections = values;
                    } else root.remember = checked;
                }
            }
            Item { Layout.fillWidth: true }
            ShellButton {
                visible: root.sharing && root.tab === "screen"; enabled: root.canSelectRegion
                theme: portalTheme; text: "Select region…"; textTint: portalTheme.overviewInk
                radius: height / 2
                color: hovered && enabled ? portalTheme.overviewButtonHover : portalTheme.overviewButton
                onClicked: root.decide(0, true)
            }
            PortalButton { id: cancel; visible: !root.sharing; theme: portalTheme; text: root.permission ? root.requestData.denyLabel || "Deny" : "Cancel"; enabled: !root.submitting; onClicked: root.decide(1) }
            PortalButton { theme: portalTheme; text: root.sharing ? "Share" : root.permission ? root.requestData.grantLabel || "Allow" : "Open"; primary: true; enabled: root.canAccept && !root.submitting; onClicked: root.decide(0) }
        }
    }
    Ember {
        id: dialogEmber
        anchors.fill: parent; z: 2
        color: portalTheme.focusColor
        restingTarget: root.sharedEmber ? null : root.emberTarget
        active: !root.sharedEmber && root.enabled && !!target
    }
}
