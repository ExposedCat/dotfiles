import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Run with a shell fixture on the isolated helper's nested Wayland compositor.
Scope {
    id: test
    property var app: null
    property int step: 0
    property real clockX: 0
    property real micX: 0
    property var portal: ({id: 10, name: "xdg-desktop-portal-hyprland",
                          properties: {"media.name": "xdph-streaming-test"}})
    property var otherShare: ({id: 11, name: "xdph-streaming-other"})
    property var idleShare: ({id: 12, name: "xdph-streaming-idle"})
    property var camera: ({id: 20, name: "camera", properties: {"media.name": "Camera"}})
    property var mic: ({id: 30, name: "Test microphone", type: PwNodeType.AudioSource})
    property var speakers: ({id: 31, name: "Test speakers", type: PwNodeType.AudioSink})
    property var recorder: ({id: 32, type: PwNodeType.AudioInStream})
    function check(value, message) {
        if (!value) { console.error("SHARING FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function find(item, predicate) {
        if (predicate(item)) return item;
        for (const child of item.children || []) { const found = find(child, predicate); if (found) return found; }
        return null;
    }
    function state(sources, links) {
        app.fixtureData = {recording: true, screenSources: sources, screenLinks: links};
    }
    function button(name) { return find(app.pill.contentItem, c => c.objectName === name); }
    function position(item) { return item.mapToItem(app.pill.contentItem, 0, 0).x; }
    function clock() { return find(app.pill.contentItem, c => /^\d\d:\d\d$/.test(c.text)); }
    function expect(active, message) {
        check(app.screenSharing === active, message);
        const indicator = find(app.pill.contentItem, c => c.objectName === "pillScreenSharingIndicator");
        check(!!indicator && indicator.visible === active, "Indicator visibility: " + message);
        check(!find(app.pill.contentItem, c => c.hint === "Stop recording"), "Recording button returned");
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "Private fixture required");
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(c.status === Component.Ready, c.errorString());
        app = c.createObject(test);
        check(!!app, "Shell creation failed");
    }
    Timer {
        interval: 300; repeat: true; running: !!test.app
        onTriggered: {
            switch (test.step++) {
            case 0: test.state([], []); break;
            case 1:
                test.expect(false, "Local recording alone must have no icon");
                test.state([test.camera], [{source:test.camera, state:PwLinkState.Active}]); break;
            case 2:
                test.expect(false, "Camera is not a screen share");
                test.state([test.portal], []); break;
            case 3:
                test.expect(false, "Unconsumed portal stream is not sharing");
                test.state([test.portal], [{source:test.portal, state:PwLinkState.Paused}]); break;
            case 4:
                test.expect(false, "Paused stream is not actively sharing");
                test.state([test.portal], [{source:test.portal, state:PwLinkState.Active},
                                          {source:test.portal, state:PwLinkState.Active}]); break;
            case 5:
                test.expect(true, "Active share must show the icon");
                test.state([test.portal], [{source:test.portal, state:PwLinkState.Active}]); break;
            case 6:
                test.expect(true, "One consumer stopping must keep the remaining share visible");
                test.state([], [{source:test.portal, state:PwLinkState.Active}]); break;
            case 7:
                test.expect(false, "Removed source must clear the icon even before links disappear");
                test.state([], []); break;
            case 8:
                test.expect(false, "Stopped share must clear the icon");
                test.clockX = test.position(test.clock());
                test.app.fixtureData = {
                    audioInputs: [test.mic], audioOutputs: [test.speakers],
                    micLinks: [
                        {source:test.speakers, target:test.recorder, state:PwLinkState.Active},
                        {source:test.mic, target:test.recorder, state:PwLinkState.Paused}
                    ]
                }; break;
            case 9:
                test.check(!test.button("pillMicrophoneIndicator").visible, "Idle mic and speaker capture must stay hidden");
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {micLinks: [
                    {source:test.mic, target:test.recorder, state:PwLinkState.Active}
                ]}); break;
            case 10: {
                const mic = test.button("pillMicrophoneIndicator");
                const layout = test.find(test.app.pill.contentItem, c => c.text === test.app.layoutLabel);
                test.check(test.app.pill.pillState === "compact" && mic.visible && mic.icon === "mic", "Active mic must show in the compact pill");
                test.micX = test.position(mic);
                test.check(test.micX > test.position(layout) + layout.width, "Mic must follow the layout without notifications");
                test.app.notifications.entries = [{id:"dot", app:"Messages", summary:"New message", time:Date.now(), read:false}];
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {
                    screenSources:[test.portal, test.otherShare, test.idleShare, test.camera],
                    screenLinks:[{source:test.portal, state:PwLinkState.Active}, {source:test.otherShare, state:PwLinkState.Active},
                        {source:test.idleShare, state:PwLinkState.Paused}, {source:test.camera, state:PwLinkState.Active}]
                }); break;
            }
            case 11: {
                const dot = test.button("pillNotificationIndicator");
                const mic = test.button("pillMicrophoneIndicator");
                const share = test.button("pillScreenSharingIndicator");
                test.check(test.position(test.clock()) === test.clockX, "Indicators moved the clock");
                test.check(dot.visible && test.position(mic) > test.micX && test.position(mic) > test.position(dot) + dot.width,
                    "Mic must follow the notification dot");
                test.check(share.visible && test.position(share) > test.position(mic) + mic.width, "Share must follow the mic");
                test.check(test.position(share) + share.width < test.app.pill.pillGeometry.x + test.app.pill.pillGeometry.width,
                    "Share button must fit inside the compact pill");
                const sound = test.find(test.app.pill.contentItem, c => c.hint === "Sound");
                test.check(mic.iconSize === sound.iconSize && share.iconSize === sound.iconSize,
                    "Privacy icons must match the sound button's icon size");
                test.check(test.app.audio.armed, "Audio feedback must be armed before testing clicks");
                mic.clicked(Qt.LeftButton);
                test.check(mic.visible && mic.icon === "mic-off" && mic.hint === "Unmute microphone", "Mic must remain visible and show mute after clicking");
                test.check(!test.app.osd.visible, "Clicking the microphone must not show the level bar");
                mic.clicked(Qt.LeftButton);
                test.check(mic.icon === "mic", "Second click must unmute the mic");
                test.check(!test.app.osd.visible, "Unmuting from the pill must not show the level bar");
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {micMuted: true});
                test.check(test.app.osd.visible && test.app.osd.kind === "microphone",
                    "External mute changes must still show microphone feedback");
                test.app.osd.visible = false;
                share.clicked(Qt.LeftButton);
                test.expect(false, "Click must stop both active shares");
                test.check(test.app.fixtureData.screenSources.includes(test.idleShare) && test.app.fixtureData.screenSources.includes(test.camera),
                    "Stop sharing must preserve the idle share and camera");
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {
                    micLinks: [], screenSources: [test.otherShare], screenLinks: [{source:test.otherShare, state:PwLinkState.Active}]
                }); break;
            }
            case 12:
                test.expect(true, "Share control must work without an active mic");
                test.check(!test.button("pillMicrophoneIndicator").visible, "Stopping the mic must clear its indicator");
                test.button("pillScreenSharingIndicator").clicked(Qt.LeftButton);
                test.expect(false, "Share-only button must stop sharing");
                console.warn("SHARING PASS: active and paused links, multiple shares, compact placement, mute and unmute, stop sharing");
                Qt.quit();
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: test.check(false, "Timed out") }
}
