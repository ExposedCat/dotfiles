import QtQuick
import Quickshell

Scope {
    id: test
    property var app: null
    property int step: 0
    property var launcher: null
    property var mixer: null
    property var notificationDeadline: 0
    function check(condition, message) {
        if (!condition) { console.error("FEATURE FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function search() { return launcher.children.find(c => c.objectName === "pillSearch"); }
    function entry(id) { return {id: id, app: "Fixture", summary: "Message " + id, body: "Notification in the pill", time: Date.now(), read: false, critical: false}; }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "A fixture is required");
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(c.status === Component.Ready, c.errorString());
        app = c.createObject(test);
        app.fixtureData = Object.assign({}, app.fixtureData, {apps: [
            {id: "terminal.desktop", name: "Terminal", description: "Command line", keywords: []},
            {id: "telegram.desktop", name: "Telegram", description: "Messaging", keywords: []}
        ]});
        app.toggle("launcher");
        advance.start();
    }
    Timer {
        id: advance
        interval: 400; repeat: true
        onTriggered: {
            const bar = test.app.pill;
            switch (test.step++) {
            case 0:
                test.launcher = bar.activePane;
                test.check(!!test.launcher, "Launcher did not open");
                test.search().text = "trm";
                break;
            case 1:
                test.check(test.launcher.matches.length > 0 && test.launcher.matches[0].id === "terminal.desktop", "Fuzzy search did not match a subsequence");
                test.search().text = "12 * (3 + 4)";
                break;
            case 2:
                test.check(test.launcher.calculation.ok && test.launcher.calculation.value === 84, "Calculator result is incorrect");
                test.launcher.copyResult();
                test.check(test.launcher.copied, "Calculator copy action failed");
                test.search().text = "-2^2";
                break;
            case 3:
                test.check(test.launcher.calculation.value === -4, "Exponent precedence is incorrect");
                test.search().text = "trm";
                test.app.applications.record("telegram.desktop");
                test.app.panel = "";
                break;
            case 4:
                test.check(!!bar.retained.launcher && !bar.activePane, "Launcher was not retained after closing");
                test.app.toggle("launcher");
                break;
            case 5:
                test.check(bar.activePane === test.launcher && test.search().text === "trm", "Reopening lost the launcher or its search");
                test.search().text = "";
                break;
            case 6:
                test.check(test.launcher.matches[0].id === "telegram.desktop", "Usage ranking was not applied");
                test.app.toggle("media");
                break;
            case 7:
                test.check(bar.pillState === "media", "Media view did not open");
                test.app.media.action("toggle");
                test.check(!test.app.media.playing, "Media play/pause failed");
                test.app.media.action("seek", 120);
                test.check(test.app.media.position === 120, "Media seek failed");
                test.app.toggle("mixer");
                break;
            case 8:
                test.mixer = bar.activePane;
                test.check(test.app.brightness.devices.length > 0, "Brightness controls did not load");
                test.app.audio.setVolume(0.25, false);
                test.check(test.app.audio.volume === 0.25, "Volume control failed");
                test.app.audio.toggleMicMute();
                test.check(test.app.audio.micMuted, "Microphone mute failed");
                test.app.brightness.setLevel("DP-3", 0.4);
                test.check(test.app.brightness.devices[0].level === 0.4, "Brightness control failed");
                test.app.toggle("system");
                break;
            case 9:
                test.check(bar.pillState === "system" && test.app.stats.sample.memory > 0 && test.app.stats.active, "System statistics did not start");
                test.app.panel = ""; test.app.pill.hoverExpanded = false;
                test.app.osd.showBrightness("DP-3", 60, 100);
                break;
            case 10:
                test.check(bar.pillState === "osd" && !test.app.stats.active, "OSD did not use the pill, or stats kept polling while closed");
                test.app.osd.visible = false;
                test.app.notifications.showPopup(test.entry("one"));
                test.app.notifications.showPopup(test.entry("two"));
                break;
            case 11:
                test.check(bar.pillState === "compact", "A corner notification expanded the pill");
                test.check(test.app.notifications.popups.length === 2 && test.app.notifications.queuedPopups.length === 0, "Corner notification arrivals did not stack");
                test.app.notifications.hoverPopup("one", true);
                test.check(test.app.notifications.bannerFrozen, "Notification hover did not pause expiry");
                test.app.osd.showAudio(false, 0.5, false);
                test.check(bar.pillState === "osd", "Corner notification hover blocked independent pill feedback");
                test.app.osd.visible = false;
                test.app.notifications.hoverPopup("one", false);
                test.app.notifications.hidePopup("one");
                break;
            case 12:
                test.check(test.app.notifications.popups[0]?.id === "two", "Next notification was not presented");
                test.app.toggle("mixer");
                break;
            case 13:
                test.check(bar.activePane === test.mixer && !test.app.notifications.bannerFrozen, "Retained mixer or independent corner banners failed");
                test.app.gesture("hide", "100");
                break;
            case 14:
                test.check(bar.pillState === "hidden" && bar.mask.regions.length === 0, "Hold did not hide the new view");
                test.app.gesture("show", "200");
                break;
            case 15:
                test.check(bar.pillState === "mixer" && bar.activePane === test.mixer, "Release did not restore the retained view");
                console.warn("FEATURE PASS: fuzzy search, calculator/copy/precedence, usage ranking, retained views, media controls/seek, mixer/brightness, active-only stats, in-pill OSD, corner notification stacking/hover, and Super restoration");
                Qt.quit();
            }
        }
    }
    Timer { interval: 18000; running: true; onTriggered: test.check(false, "Timed out"); }
}
