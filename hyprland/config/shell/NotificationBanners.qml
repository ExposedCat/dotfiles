import QtQuick

Item {
    id: root
    required property var theme
    required property var store
    property bool active: true
    readonly property Item controlEmber: bannerEmber
    property var popupData: ({})
    property int presentationSerial: 0
    property int regionRevision: 0
    readonly property int presentationCount: popupModel.count
    readonly property bool groupsUnfolded: {
        const revision = regionRevision;
        for (let i = 0; i < banners.count; ++i) {
            const banner = banners.itemAt(i);
            if (banner && (banner.expanded || banner.unfold > 0)) return true;
        }
        return false;
    }
    readonly property var inputRegions: {
        const revision = regionRevision;
        const regions = [];
        for (let i = 0; i < banners.count; ++i) {
            const banner = banners.itemAt(i);
            if (banner) regions.push(banner.inputRegion);
        }
        return regions;
    }
    implicitHeight: column.implicitHeight

    function syncPopups() {
        const groups = active ? store.popupGroups : [];
        const data = Object.assign({}, popupData);
        const used = new Set();
        for (let i = 0; i < groups.length; ++i) {
            const group = groups[i];
            let at = -1;
            // Keep the surface when its newest message changes, or a replacement
            // changes its title. Updating content must not replay the entrance.
            for (let j = 0; j < popupModel.count; ++j) {
                const id = popupModel.get(j).entryId;
                if (!used.has(id) && data[id].key === group.key) { at = j; break; }
            }
            if (at < 0) for (let j = 0; j < popupModel.count; ++j) {
                const id = popupModel.get(j).entryId;
                if (!used.has(id) && data[id].entries.some(old => group.entries.some(entry => entry.id === old.id))) { at = j; break; }
            }
            let id = at < 0 ? group.entries[0].id : popupModel.get(at).entryId;
            // A title change can split the original member out of a stack
            // whose surface still uses that member's ID.
            if (at < 0 && popupData[id]) id += "#" + (++presentationSerial);
            data[id] = group;
            used.add(id);
            popupData = Object.assign({}, data);
            if (at < 0) popupModel.insert(i, {entryId: id, wanted: true});
            else {
                popupModel.setProperty(at, "wanted", true);
                if (at !== i) popupModel.move(at, i, 1);
            }
        }
        for (let i = 0; i < popupModel.count; ++i)
            popupModel.setProperty(i, "wanted", used.has(popupModel.get(i).entryId));
        popupData = data;
    }
    function retire(id) {
        for (let i = 0; i < popupModel.count; ++i) {
            if (popupModel.get(i).entryId !== id) continue;
            if (popupModel.get(i).wanted) return;
            popupModel.remove(i);
            break;
        }
        const data = Object.assign({}, popupData); delete data[id]; popupData = data;
    }
    onActiveChanged: syncPopups()
    Connections { target: root.store; function onPopupGroupsChanged() { root.syncPopups(); } }
    Component.onCompleted: syncPopups()
    ListModel { id: popupModel }
    Column {
        id: column
        width: parent.width - root.theme.panelGap
        spacing: 14
        move: Transition {
            // Expanded/hovered cards already animate their height. Follow that
            // geometry directly so neighboring banners cannot overlap it.
            enabled: !root.groupsUnfolded && !root.store.bannerFrozen
            NumberAnimation { property: "y"; duration: 260; easing.type: Easing.OutCubic }
        }
        Repeater {
            id: banners
            model: popupModel
            onItemAdded: root.regionRevision++
            onItemRemoved: root.regionRevision++
            NotificationBanner {
                required property string entryId
                required property bool wanted
                objectName: "banner:" + entryId
                width: column.width
                theme: root.theme; store: root.store; group: root.popupData[entryId]
                presented: wanted
                onRetired: root.retire(entryId)
            }
        }
    }
    Ember {
        id: bannerEmber
        anchors.fill: parent
        z: 2
        color: root.theme.focusColor
        active: root.active && !!target
    }
}
