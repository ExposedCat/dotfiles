import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Scope {
    id: root
    property bool fixture: false
    property var fixtureData: ({})
    property bool deviceControlsOpen: false
    property string basicOutputName: ""
    readonly property var nodes: fixture ? [] : Pipewire.nodes.values.filter(n => n && n.audio && !n.isStream)
    readonly property var outputs: fixture ? (fixtureData.audioOutputs || [{id: 1, name: "fixture-output", description: "Speakers"}]) : nodes.filter(n => n.isSink)
    readonly property var inputs: fixture ? (fixtureData.audioInputs || [{id: 2, name: "fixture-input", description: "Microphone"}]) : nodes.filter(n => !n.isSink)
    readonly property var sink: fixture ? outputs.find(n => n.id === fixtureData.outputId) || outputs[0] || null : Pipewire.defaultAudioSink
    readonly property var source: fixture ? inputs.find(n => n.id === fixtureData.inputId) || inputs[0] || null : Pipewire.defaultAudioSource
    readonly property bool available: fixture || !!(sink && sink.audio && sink.ready)
    readonly property real volume: fixture ? (fixtureData.volume ?? 0.5) : available ? sink.audio.volume : 0
    readonly property bool muted: fixture ? !!fixtureData.muted : available ? sink.audio.muted : false
    readonly property real micVolume: fixture ? (fixtureData.micVolume ?? 0.8) : source && source.audio && source.ready ? source.audio.volume : 0
    readonly property bool micMuted: fixture ? !!fixtureData.micMuted : source && source.audio ? source.audio.muted : false
    // An AudioSink can feed a recording stream through its monitor ports.
    readonly property var micLinks: (fixture ? fixtureData.micLinks || [] : Pipewire.linkGroups.values)
        .filter(link => link?.source?.type === PwNodeType.AudioSource && link.target?.type === PwNodeType.AudioInStream)
    readonly property var activeMics: [...new Set(micLinks.filter(link => link.state === PwLinkState.Active).map(link => link.source))]
    readonly property bool micInUse: activeMics.length > 0
    readonly property bool activeMicsMuted: micInUse && (fixture ? micMuted : activeMics.every(node => node.audio?.muted))
    readonly property string device: sink ? (sink.description || sink.name) : "Audio unavailable"
    property bool armed: false
    property bool togglingActiveMics: false
    signal osdRequested(bool microphone)
    signal fixtureMicMuteRequested(bool muted)
    function show(mic) { if (armed && !(mic && togglingActiveMics)) osdRequested(mic); }
    function adjust(delta) { if (available && !fixture) sink.audio.volume = Math.max(0, Math.min(1, volume + delta)); }
    function toggleMute() { if (fixture) fixtureData = Object.assign({}, fixtureData, {muted: !muted}); else if (available) sink.audio.muted = !muted; }
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
    function toggleActiveMics() {
        if (!micInUse) return;
        const mute = !activeMicsMuted;
        // The pill icon provides immediate feedback for this toggle.
        togglingActiveMics = true;
        try {
            if (fixture) { fixtureMicMuteRequested(mute); return; }
            for (const node of activeMics) {
                if (node.audio) node.audio.muted = mute;
            }
        } finally {
            togglingActiveMics = false;
        }
    }
    function selectDevice(index, microphone) {
        const node = (microphone ? inputs : outputs)[index];
        if (!node) return;
        if (fixture) { fixtureData = Object.assign({}, fixtureData, microphone ? {inputId: node.id} : {outputId: node.id}); return; }
        if (microphone) Pipewire.preferredDefaultAudioSource = node;
        else Pipewire.preferredDefaultAudioSink = node;
    }
    function matchesBluetoothOutput(node, address) {
        const mac = address.toLowerCase().replace(/:/g, "_");
        const name = node.name.toLowerCase();
        return name.startsWith("bluez_output." + mac + ".")
            || name === "bluez_output." + mac
            || node.properties?.["api.bluez5.address"]?.toLowerCase() === address.toLowerCase();
    }
    function bluetoothOutput(address) {
        if (sink && matchesBluetoothOutput(sink, address)) return sink;
        return outputs.find(node => matchesBluetoothOutput(node, address)) || null;
    }
    function alternativeOutput(address) {
        const others = outputs.filter(node => !matchesBluetoothOutput(node, address));
        return others.find(node => node.name === basicOutputName)
            || others.find(node => !node.name.startsWith("bluez_output."))
            || others[0] || null;
    }
    function toggleBluetoothOutput(address) {
        const node = bluetoothOutput(address), other = alternativeOutput(address);
        if (node && other) selectDevice(outputs.indexOf(sink === node ? other : node), false);
    }
    onVolumeChanged: show(false)
    onMutedChanged: show(false)
    onMicVolumeChanged: show(true)
    onMicMutedChanged: show(true)
    onSinkChanged: {
        if (sink && !sink.name.startsWith("bluez_output.")) basicOutputName = sink.name;
        armed = false;
        arm.restart();
    }
    onSourceChanged: { armed = false; arm.restart(); }
    PwObjectTracker { objects: root.fixture ? [] : [...new Set((root.deviceControlsOpen ? root.nodes : root.activeMics).concat([root.sink, root.source]).filter(n => n !== null))] }
    PwObjectTracker { objects: root.fixture ? [] : root.micLinks }
    Timer { id: arm; interval: 700; running: true; onTriggered: root.armed = true }
}
