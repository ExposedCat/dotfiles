import QtQuick
import Quickshell

// Run on an isolated nested Wayland compositor with DOTFILES_SHELL_FIXTURE,
// DOTFILES_SHELL_SOURCE and test-only XDG_STATE_HOME / XDG_CACHE_HOME.
Scope {
    id: test
    property var app: null
    property int step: 0
    property var clockText: null
    property real clockX: 0
    property bool watchClosing: false
    property rect closingGeometry
    property int closingFrames: 0
    function findItem(item, predicate) {
        if (predicate(item)) return item;
        for (const child of item.children || []) {
            const found = findItem(child, predicate);
            if (found) return found;
        }
        return null;
    }
    function check(condition, message) {
        if (!condition) { console.error("PILL FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "A fixture is required");
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(component.status === Component.Ready, component.errorString());
        app = component.createObject(test);
        check(!!app, "Shell could not be created");
        app.fixtureData = Object.assign({}, app.fixtureData, {apps: [
            {id: "telegram.desktop", name: "Telegram", description: "Messaging", keywords: []},
            {id: "terminal.desktop", name: "Terminal", description: "Command line", keywords: []}
        ]});
        advance.start();
    }
    Timer {
        id: advance
        interval: 400; repeat: true
        onTriggered: {
            const bar = test.app.pill;
            const pill = bar.pillGeometry;
            switch (test.step++) {
            case 0:
                test.check(bar.pillState === "compact" && Math.abs(pill.width - bar.compactWidth) < 1, "Initial compact geometry");
                test.check(bar.exclusionMode === ExclusionMode.Ignore && pill.y === 12, "Pill must float without reserving app space");
                test.clockText = test.findItem(bar.contentItem, item => item.text === Qt.formatDateTime(test.app.clock.date, "hh:mm"));
                test.check(!!test.clockText, "Clock text is missing");
                test.clockX = test.clockText.mapToItem(bar.contentItem, 0, 0).x;
                test.check(!test.findItem(bar.contentItem, item => item.objectName === "pillNotificationIndicator").visible, "Unlit notification indicator must be absent");
                bar.hoverExpanded = true;
                break;
            case 1:
                test.check(bar.pillState === "expanded" && pill.width > bar.compactWidth && pill.height === 40, "Hover expansion");
                test.check(bar.workspaceInset === 20, "Workspaces must stay at the left inset");
                test.check(test.findItem(bar.contentItem, item => item.text === Qt.formatDateTime(test.app.clock.date, "MMM d, ddd")).opacity === 1, "Expanded date is missing");
                test.app.gesture("tap", "100");
                break;
            case 2:
                test.check(bar.pillState === "launcher" && pill.height > 400 && !!bar.activePane, "Launcher expansion");
                test.closingGeometry = bar.paneGeometry;
                test.watchClosing = true;
                test.app.gesture("tap", "200");
                test.check(bar.paneGeometry === test.closingGeometry, "Popup content jumped at the start of closing");
                break;
            case 3:
                test.watchClosing = false;
                test.check(test.closingFrames >= 2, "Closing motion was not sampled");
                test.check(bar.pillState === "compact" && Math.abs(pill.width - bar.compactWidth) < 1 && !bar.activePane, "Launcher must fully collapse and unload: state=" + bar.pillState + ", width=" + pill.width + ", compact=" + bar.compactWidth + ", shown=" + bar.shownPanel + ", pane=" + !!bar.activePane);
                test.app.toggle("ethernet");
                test.app.toggle("bluetooth");
                break;
            case 4:
                test.check(bar.pillState === "bluetooth" && !!bar.activePane, "Immediate menu switching");
                test.app.toggle("power");
                break;
            case 5:
                test.check(bar.pillState === "power" && !!bar.activePane, "Power view");
                test.app.gesture("hide", "300");
                break;
            case 6:
                test.check(bar.pillState === "hidden" && bar.mask.regions.length === 0 && test.app.panel === "power", "Holding must hide and relinquish input");
                test.app.gesture("show", "400");
                test.app.gesture("hide", "300");
                test.check(bar.pillState === "power", "Release restores the existing view");
                test.app.panel = "";
                break;
            case 7:
                test.check(bar.pillState === "compact" && bar.mask.regions.length === 1, "Release restores compact; stale hide is ignored");
                test.app.gestureTimestamp = 4294967200;
                test.app.gesture("hide", "4294967250");
                test.app.gesture("show", "20");
                test.app.gesture("hide", "4294967250");
                break;
            case 8:
                test.check(bar.pillState === "compact", "Input timestamps must survive wraparound");
                test.app.gesture("hide", "25");
                test.app.gesture("launcher", "30");
                test.app.gesture("hide", "25");
                break;
            case 9:
                test.check(bar.pillState === "launcher", "Super shortcut must open despite a delayed hide");
                bar.activePane.children.find(c => c.objectName === "pillSearch").text = "Tele";
                break;
            case 10:
                test.check(bar.activePane.matches.length === 1 && bar.activePane.matches[0].id === "telegram.desktop", "Launcher search filtering");
                bar.activePane.launch();
                break;
            case 11:
                test.check(bar.pillState === "compact", "Launching an application must close the launcher");
                test.app.gesture("tap", "40");
                break;
            case 12:
                bar.activePane.children.find(c => c.objectName === "pillSearch").text = "no-such-application";
                break;
            case 13:
                test.check(bar.activePane.matches.length === 0, "Empty search results");
                bar.activePane.launch();
                test.check(test.app.panel === "launcher", "Empty results must not launch");
                test.app.toggle("notifications");
                break;
            case 14:
                test.check(bar.pillState === "notifications" && !!bar.activePane && pill.height > 500, "Notification center view");
                test.app.panel = "";
                break;
            case 15:
                test.check(bar.pillState === "compact", "Notification center dismissal");
                console.warn("PILL PASS: stationary clock, frozen closing content, fixed radius/left inset, hidden inactive indicator, hover date, launcher search/launch, menu switching, holds, and timestamp wraparound");
                Qt.quit();
            }
        }
    }
    Timer {
        interval: 16; repeat: true; running: !!test.clockText
        onTriggered: {
            const bar = test.app.pill;
            test.check(test.clockText.mapToItem(bar.contentItem, 0, 0).x === test.clockX, "Clock shook during morph");
            test.check(bar.pillRadius === 20 && bar.workspaceInset === 20, "Corner radius or workspace inset changed during morph");
            test.check(Number.isInteger(bar.pillGeometry.x) && Number.isInteger(bar.pillGeometry.width), "Fractional pill geometry");
            if (test.watchClosing && bar.activePane) {
                test.closingFrames++;
                test.check(bar.paneGeometry === test.closingGeometry, "Closing content was resized or moved");
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: test.check(false, "Timed out"); }
}
