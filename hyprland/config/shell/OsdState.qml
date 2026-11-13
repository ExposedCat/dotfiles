import QtQuick
import Quickshell

Scope {
    id: root
    property bool visible: false
    property string kind: "volume"
    property string output: ""
    property real level: 0
    property bool muted: false
    readonly property string title: kind === "brightness" ? "Brightness · " + output : kind === "microphone" ? "Microphone" : "Volume"
    readonly property string icon: kind === "brightness" ? "sun" : kind === "microphone" ? (muted ? "mic-off" : "mic") : (muted ? "volume-x" : "volume-2")
    readonly property string valueText: muted ? "Muted" : Math.round(level * 100) + "%"
    function showAudio(microphone, value, mute) {
        kind = microphone ? "microphone" : "volume";
        output = "";
        level = Math.max(0, value);
        muted = mute;
        visible = true;
        hide.restart();
    }
    function showBrightness(monitor, current, maximum) {
        if (!monitor || !Number.isFinite(current) || !Number.isFinite(maximum)
                || maximum <= 0 || current < 0 || current > maximum) return;
        kind = "brightness";
        output = monitor;
        level = current / maximum;
        muted = false;
        visible = true;
        hide.restart();
    }
    Timer { id: hide; interval: 1600; onTriggered: root.visible = false }
}
