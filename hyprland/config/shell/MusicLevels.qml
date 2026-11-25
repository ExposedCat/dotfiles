import QtQuick
import Quickshell
import Quickshell.Io

// Stereo band levels of the speaker output, bass first. Runs only while active.
Scope {
    id: root
    required property var shell
    property bool active: false
    readonly property int bands: 6
    property var left: zeros()
    property var right: zeros()
    // Counts detected kicks; beatStrength (0..1) belongs to the latest one.
    property int beats: 0
    property real beatStrength: 0
    readonly property string sinkName: shell.audio.sink?.name ?? ""
    function zeros() { return Array(bands).fill(0); }
    function reset() { left = zeros(); right = zeros(); }
    onActiveChanged: { if (!active) reset(); }
    // The monitor stream binds to the sink that was default when it started.
    onSinkNameChanged: { if (reader.running) { reader.running = false; restart.restart(); } }
    Timer { id: restart; interval: 50; onTriggered: reader.running = Qt.binding(() => root.active && !root.shell.fixture) }

    Process {
        id: reader
        command: [root.shell.backend, "shell", "audio-levels"]
        running: root.active && !root.shell.fixture
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    root.left = data.l; root.right = data.r;
                    if (data.beat > 0) { root.beatStrength = data.beat; root.beats++; }
                } catch (e) {}
            }
        }
        onExited: (code, status) => root.reset()
    }

    // Fixture sessions get a deterministic 118 BPM signal panning side to side.
    Timer {
        interval: 33; repeat: true
        running: root.active && root.shell.fixture
        property real t: 0
        property int lastBeat: -1
        onTriggered: {
            t += interval / 1000;
            const beatLength = 60 / 118, phase = (t % beatLength) / beatLength, beat = Math.floor(t / beatLength);
            const kick = Math.exp(-phase * 6), pan = Math.sin(t * 0.6);
            const make = side => Array.from({length: root.bands}, (_, i) => {
                const f = i / (root.bands - 1);
                const value = (1 - f) * 0.75 * kick + 0.3 * Math.sin(t * (1 + 2.5 * f) + i) ** 2;
                return Math.max(0, Math.min(1, value * (1 + side * pan * 0.7)));
            });
            root.left = make(-1); root.right = make(1);
            if (beat !== lastBeat) { lastBeat = beat; root.beatStrength = beat % 4 === 0 ? 1 : 0.6; root.beats++; }
        }
    }
}
