import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Scope {
    id: root
    property bool fixture: false
    property var fixtureData: ({})
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
    onVolumeChanged: show(false)
    onMutedChanged: show(false)
    onMicVolumeChanged: show(true)
    onMicMutedChanged: show(true)
    onSinkChanged: { armed = false; arm.restart(); }
    onSourceChanged: { armed = false; arm.restart(); }
    PwObjectTracker { objects: root.fixture ? [] : [root.sink, root.source].filter(n => n !== null) }
    Timer { id: arm; interval: 700; running: true; onTriggered: root.armed = true }
}
