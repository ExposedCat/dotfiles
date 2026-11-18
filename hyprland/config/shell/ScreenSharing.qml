import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Scope {
    id: root
    property bool fixture: false
    property var fixtureData: ({})
    // Bind non-audio nodes to read media.name. PipeWire may set node.name to
    // the application name instead of XDPH's per-stream name.
    readonly property var candidates: (fixture ? fixtureData.screenSources || [] : Pipewire.nodes.values)
        .filter(n => n && !n.audio)
    // Direct region recording and screenshots create no portal sources.
    readonly property var sources: candidates.filter(n =>
        n.properties?.["media.name"]?.startsWith("xdph-streaming-") || n.name?.startsWith("xdph-streaming-"))
    readonly property var links: (fixture ? fixtureData.screenLinks || [] : Pipewire.linkGroups.values)
        .filter(link => link && link.source && sources.some(node => node.id === link.source.id))
    readonly property var activeSources: sources.filter(node =>
        links.some(link => link.source?.id === node.id && link.state === PwLinkState.Active))
    readonly property bool active: activeSources.length > 0
    signal fixtureSharesStopped(var remainingSources)

    function stop() {
        if (fixture) {
            fixtureSharesStopped(candidates.filter(node => !activeSources.includes(node)));
            return;
        }
        // Removing the portal source disconnects every consumer of that share.
        for (const node of activeSources) Quickshell.execDetached(["pw-cli", "destroy", String(node.id)]);
    }
    PwObjectTracker { objects: root.fixture ? [] : root.candidates }
    PwObjectTracker { objects: root.fixture ? [] : root.links }
}
