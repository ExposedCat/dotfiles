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
        (n.properties?.["media.name"] || n.name || "").startsWith("xdph-streaming-"))
    readonly property var links: (fixture ? fixtureData.screenLinks || [] : Pipewire.linkGroups.values)
        .filter(link => link && link.source && sources.some(node => node.id === link.source.id))
    readonly property bool active: links.some(link => link.state === PwLinkState.Active)
    PwObjectTracker { objects: root.fixture ? [] : root.candidates }
    PwObjectTracker { objects: root.fixture ? [] : root.links }
}
