import QtQuick

Item {
    id: root
    required property var theme
    required property var store
    property bool active: true
    property var popupData: ({})
    property int regionRevision: 0
    readonly property int presentationCount: popupModel.count
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
        const entries = active ? store.popups : [];
        const data = Object.assign({}, popupData);
        for (const entry of entries) data[entry.id] = entry;
        popupData = data;
        const keys = entries.map(entry => entry.id);
        for (let i = 0; i < popupModel.count; ++i)
            popupModel.setProperty(i, "wanted", keys.includes(popupModel.get(i).entryId));
        for (let i = 0; i < keys.length; ++i) {
            let at = -1;
            for (let j = 0; j < popupModel.count; ++j)
                if (popupModel.get(j).entryId === keys[i]) { at = j; break; }
            if (at < 0) popupModel.insert(i, {entryId: keys[i], wanted: true});
            else if (at !== i) popupModel.move(at, i, 1);
        }
    }
    function retire(id) {
        if (active && store.popups.some(entry => entry.id === id) && !store.removing[id]) return;
        for (let i = 0; i < popupModel.count; ++i) {
            if (popupModel.get(i).entryId === id) { popupModel.remove(i); break; }
        }
        const data = Object.assign({}, popupData); delete data[id]; popupData = data;
    }
    onActiveChanged: syncPopups()
    Connections { target: root.store; function onPopupsChanged() { root.syncPopups(); } }
    Component.onCompleted: syncPopups()
    ListModel { id: popupModel }
    Column {
        id: column
        width: parent.width - root.theme.panelGap
        spacing: 14
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
                theme: root.theme; store: root.store; entry: root.popupData[entryId]
                presented: wanted && !root.store.removing[entryId]
                onRetired: root.retire(entryId)
            }
        }
    }
}
