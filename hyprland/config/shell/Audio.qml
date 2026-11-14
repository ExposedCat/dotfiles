import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Scope {
    id: root
    property bool fixture: false
    property var fixtureData: ({})
    property bool mixerOpen: false
    readonly property var nodes: fixture ? [] : Pipewire.nodes.values.filter(n => n && n.audio && !n.isStream)
    readonly property var outputs: fixture ? [{id: 1, name: "fixture-output", description: "Speakers"}] : nodes.filter(n => n.isSink)
    readonly property var inputs: fixture ? [{id: 2, name: "fixture-input", description: "Microphone"}] : nodes.filter(n => !n.isSink)
    readonly property var sink: fixture ? null : Pipewire.defaultAudioSink
    readonly property var source: fixture ? null : Pipewire.defaultAudioSource
    readonly property bool available: fixture || !!(sink && sink.audio && sink.ready)
    readonly property real volume: fixture ? (fixtureData.volume ?? 0.5) : available ? sink.audio.volume : 0
    readonly property bool muted: fixture ? !!fixtureData.muted : available ? sink.audio.muted : false
    readonly property real micVolume: fixture ? (fixtureData.micVolume ?? 0.8) : source && source.audio && source.ready ? source.audio.volume : 0
    readonly property bool micMuted: fixture ? !!fixtureData.micMuted : source && source.audio ? source.audio.muted : false
    readonly property string device: fixture ? "Speakers" : available ? (sink.description || sink.name) : "Audio unavailable"
    property bool armed: false
    signal osdRequested(bool microphone)
    function show(mic) { if (armed) osdRequested(mic); }
    function adjust(delta) { if (available && !fixture) sink.audio.volume = Math.max(0, Math.min(1, volume + delta)); }
    function toggleMute() { if (available && !fixture) sink.audio.muted = !muted; }
    function setVolume(value, microphone) {
        value = Math.max(0, Math.min(1, value));
        if (fixture) { fixtureData = Object.assign({}, fixtureData, microphone ? {micVolume: value} : {volume: value}); return; }
        const node = microphone ? source : sink;
        if (node && node.ready && node.audio) node.audio.volume = value;
    }
    function toggleMicMute() {
        if (fixture) fixtureData = Object.assign({}, fixtureData, {micMuted: !micMuted});
        else if (source && source.audio) source.audio.muted = !source.audio.muted;
    }
    function selectDevice(index, microphone) {
        if (fixture) return;
        const node = (microphone ? inputs : outputs)[index];
        if (!node) return;
        if (microphone) Pipewire.preferredDefaultAudioSource = node;
        else Pipewire.preferredDefaultAudioSink = node;
    }
    onVolumeChanged: show(false)
    onMutedChanged: show(false)
    onMicVolumeChanged: show(true)
    onMicMutedChanged: show(true)
    onSinkChanged: { armed = false; arm.restart(); }
    onSourceChanged: { armed = false; arm.restart(); }
    PwObjectTracker { objects: root.fixture ? [] : (root.mixerOpen ? root.nodes : []).concat([root.sink, root.source]).filter(n => n !== null) }
    Timer { id: arm; interval: 700; running: true; onTriggered: root.armed = true }
}
