import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var shell
    required property var theme
    property real scrollBottomPadding: 0
    readonly property var vpn: shell.vpn
    property string selectedUuid: ""
    property var rowItems: ({})
    property var profileData: ({})
    readonly property Item emberTarget: rowItems[selectedUuid]?.emberSlot || null

    function selectProfile(uuid) { selectedUuid = uuid; }
    function followPointer() {
        const position = shell.pill.pointerPosition;
        for (const uuid of Object.keys(rowItems)) {
            const row = rowItems[uuid];
            if (!row.visible || !row.enabled) continue;
            const point = row.mapFromItem(shell.pill.contentItem, position.x, position.y);
            if (point.x >= 0 && point.y >= 0 && point.x < row.width && point.y < row.height) {
                selectProfile(uuid);
                return;
            }
        }
    }
    function restoreFocus() {
        if (rowItems[selectedUuid]?.enabled) rowItems[selectedUuid].forceActiveFocus();
        else root.forceActiveFocus();
    }
    function syncProfiles() {
        const profiles = vpn.profiles || [];
        const data = {};
        const keys = [];
        for (const profile of profiles) {
            data[profile.uuid] = profile;
            keys.push(profile.uuid);
        }
        profileData = data;
        for (let i = profileModel.count - 1; i >= 0; --i) {
            if (!data[profileModel.get(i).uuid]) profileModel.remove(i);
        }
        for (let i = 0; i < keys.length; ++i) {
            let at = -1;
            for (let j = i; j < profileModel.count; ++j) {
                if (profileModel.get(j).uuid === keys[i]) { at = j; break; }
            }
            if (at < 0) profileModel.insert(i, {uuid: keys[i]});
            else if (at !== i) profileModel.move(at, i, 1);
        }
        if (!keys.includes(selectedUuid)) {
            selectedUuid = keys.find(uuid => data[uuid].active) || keys[0] || "";
        }
    }

    ListModel { id: profileModel }
    Connections {
        target: root.vpn
        function onProfilesChanged() { Qt.callLater(root.syncProfiles); }
    }
    Connections {
        target: root.shell
        function onPanelChanged() { if (root.shell.panel === "vpn") Qt.callLater(root.restoreFocus); }
    }
    Connections {
        target: root.shell.pill
        function onPointerPositionChanged() { if (root.shell.panel === "vpn") root.followPointer(); }
    }
    Component.onCompleted: syncProfiles()

    spacing: 20

    RowLayout {
        Layout.fillWidth: true; spacing: 10
        ShellIcon {
            objectName: "vpn-header-icon"
            name: root.vpn.active ? "shield-check" : "shield-lock"
            tint: root.vpn.active ? root.theme.overviewAccent : root.theme.overviewInk
            Layout.preferredWidth: 22; Layout.preferredHeight: 22
        }
        Text { text: "VPN"; color: root.theme.text; font: root.theme.textFont; Layout.fillWidth: true }
    }

    ListView {
        id: list
        objectName: "vpn-profiles"
        visible: count > 0 && !root.vpn.unavailable
        Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0
        implicitHeight: visible ? Math.min(380, contentHeight) : 0
        bottomMargin: emptyState.visible ? 0 : root.scrollBottomPadding
        clip: true; spacing: 6
        model: profileModel
        boundsBehavior: Flickable.StopAtBounds
        move: Transition { NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic } }
        displaced: Transition { NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic } }
        PillWheel { id: wheel; flickable: list; duration: 150 }
        ScrollBar.vertical: ScrollBar {
            onPressedChanged: { if (pressed) wheel.stop(); }
        }
        delegate: ColumnLayout {
            id: profileRow
            required property string uuid
            required property int index
            readonly property var profile: root.profileData[uuid] || ({uuid: uuid, name: uuid, active: false, state: "disconnected"})
            readonly property bool pending: root.vpn.busy(profile)
            width: list.width; height: implicitHeight; spacing: 0

            Rectangle {
                id: button
                objectName: "vpn-profile:" + profileRow.uuid
                property alias emberSlot: profileSlot
                readonly property string hint: (profileRow.profile.active ? "Disconnect " : "Connect to ") + label.text
                Layout.fillWidth: true; implicitHeight: 48; radius: 12
                color: root.theme.overviewControls
                opacity: enabled || profileRow.pending ? 1 : 0.45
                enabled: !profileRow.pending && !root.vpn.activeJobUuid && !!root.profileData[profileRow.uuid]
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: hint
                Accessible.description: profileRow.pending
                    ? (root.vpn.pending[profileRow.uuid]?.action === "down" || profileRow.profile.state === "disconnecting" ? "Disconnecting" : "Connecting")
                    : profileRow.profile.active ? "Connected" : "Disconnected"
                function activate() { root.selectProfile(profileRow.uuid); root.vpn.toggle(profileRow.profile); }
                Accessible.onPressAction: activate()
                Keys.onReturnPressed: activate()
                Keys.onSpacePressed: activate()
                onActiveFocusChanged: { if (activeFocus) root.selectProfile(profileRow.uuid); }
                Component.onCompleted: {
                    const items = Object.assign({}, root.rowItems);
                    items[profileRow.uuid] = button;
                    root.rowItems = items;
                }
                Component.onDestruction: {
                    if (root.rowItems[profileRow.uuid] === button) {
                        const items = Object.assign({}, root.rowItems);
                        delete items[profileRow.uuid];
                        root.rowItems = items;
                    }
                }
                EmberSlot {
                    id: profileSlot
                    objectName: "vpn-row:" + profileRow.uuid
                    shell: root.shell
                    anchors.fill: parent
                    shapeRadius: button.radius
                    shapeOpacity: 0.42
                }
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 12
                    ShellIcon {
                        name: profileRow.profile.active ? "shield-check" : "shield-lock"
                        tint: profileRow.profile.active ? root.theme.overviewAccent : root.theme.overviewSecondary
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                    }
                    Text {
                        id: label
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        text: profileRow.profile.name
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: root.theme.text
                        font: root.theme.textFont
                    }
                    Spinner {
                        objectName: "vpn-pending:" + profileRow.uuid
                        running: profileRow.pending
                        visible: running
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                    }
                    ShellIcon {
                        objectName: "vpn-connected:" + profileRow.uuid
                        name: "check"
                        tint: root.theme.overviewAccent
                        visible: !!profileRow.profile.active && !profileRow.pending
                        Layout.preferredWidth: 20; Layout.preferredHeight: 20
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { button.forceActiveFocus(Qt.MouseFocusReason); button.activate(); }
                }
            }
            Text {
                Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.topMargin: 6
                text: root.vpn.errors[profileRow.uuid] || ""
                visible: text.length > 0
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: root.theme.red
                font: root.theme.textFont
            }
        }
    }

    Text {
        id: emptyState
        Layout.bottomMargin: root.scrollBottomPadding
        Layout.fillWidth: true; font: root.theme.textFont; color: root.theme.secondary; wrapMode: Text.Wrap
        visible: root.vpn.unavailable || (!root.vpn.loading && list.count === 0)
        text: root.vpn.unavailable ? "VPN unavailable" : "No VPN profiles"
    }
}
