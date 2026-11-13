import QtQuick
import Quickshell

// Run through isolated-gui with DOTFILES_SHELL_SOURCE set to config/shell.
Scope {
    id: test
    property var osd
    property var audio
    property int phase: 0
    property double started: 0
    function check(condition, message) {
        if (!condition) { console.error("OSD REGRESSION FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function load(name, parent, properties) {
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/" + name + ".qml");
        check(component.status === Component.Ready, component.errorString());
        const object = component.createObject(parent, properties || {});
        check(!!object, "Could not create " + name);
        return object;
    }
    Window {
        id: preview
        width: 600; height: 240; visible: true
        title: "Brightness OSD regression"
        color: "#68788c"
    }
    Component.onCompleted: {
        osd = load("OsdState", test);
        const palette = load("ShellTheme", test);
        const card = load("OsdCard", preview.contentItem, {osd: osd, theme: palette, x: 125, y: 76});
        card.visible = Qt.binding(() => test.osd.visible);
        audio = load("Audio", test, {fixture: true, fixtureData: {volume: 0.5}});
        audio.osdRequested.connect(microphone => osd.showAudio(microphone, microphone ? audio.micVolume : audio.volume, microphone ? audio.micMuted : audio.muted));
        check(!osd.visible, "OSD appeared at startup");
        started = Date.now();
    }
    Timer {
        interval: 20; repeat: true; running: !!test.audio
        onTriggered: {
            const elapsed = Date.now() - test.started;
            const osd = test.osd;
            if (test.phase === 0 && elapsed >= 800) {
                test.check(!osd.visible, "Audio initialization showed the OSD");
                test.audio.fixtureData = {volume: 0.65};
                test.check(osd.visible && osd.kind === "volume" && osd.valueText === "65%", "Audio did not request the shared OSD");
                osd.showBrightness("DP-3", 85, 200);
                test.check(osd.visible && osd.kind === "brightness" && osd.level === 0.425 && osd.valueText === "43%", "Brightness did not normalize the readback");
                test.check(osd.output === "DP-3" && osd.icon === "sun" && !osd.muted, "Brightness presentation is incorrect");
                osd.showBrightness("DP-1", 20, 0);
                test.check(osd.output === "DP-3", "Invalid readback replaced the OSD");
                test.phase = 1; test.started = Date.now();
            } else if (test.phase === 1 && elapsed >= 1100) {
                osd.showBrightness("DP-1", 0, 100);
                test.check(osd.valueText === "0%" && osd.output === "DP-1", "Zero brightness or monitor switch failed");
                test.phase = 2; test.started = Date.now();
            } else if (test.phase === 2 && elapsed >= 800) {
                test.check(osd.visible, "Repeat did not restart the hide timer");
                test.audio.fixtureData = {volume: 0.75};
                test.check(osd.kind === "volume" && osd.output === "" && osd.valueText === "75%", "Audio did not replace brightness");
                test.audio.fixtureData = {volume: 0.75, micMuted: true};
                test.check(osd.kind === "microphone" && osd.valueText === "Muted" && osd.icon === "mic-off", "Microphone mute OSD regressed");
                osd.showBrightness("DP-3", 100, 100);
                test.check(osd.valueText === "100%" && !osd.muted, "Brightness retained audio mute state");
                test.phase = 3; test.started = Date.now();
            } else if (test.phase === 3 && elapsed >= 1750) {
                test.check(!osd.visible, "OSD did not hide automatically");
                console.warn("OSD REGRESSION PASS: actual levels, audio/mic replacement, monitor switches, repeat timeout, auto-hide");
                Qt.quit();
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: test.check(false, "OSD sequence timed out") }
}
