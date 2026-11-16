import QtQuick
import Quickshell
import Quickshell.Wayland

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
    property int hiddenLauncherFrames: 0
    property int hiddenOpeningFrames: 0
    property int hiddenClosingFrames: 0
    property int hiddenSlidingFrames: 0
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
                test.check(bar.exclusionMode === ExclusionMode.Ignore && pill.y === bar.theme.panelGap, "Pill must float without reserving app space");
                test.clockText = test.findItem(bar.contentItem, item => item.text === Qt.formatDateTime(test.app.clock.date, "hh:mm"));
                test.check(!!test.clockText, "Clock text is missing");
                test.clockX = test.clockText.mapToItem(bar.contentItem, 0, 0).x;
                test.check(!test.findItem(bar.contentItem, item => item.objectName === "pillNotificationIndicator").visible, "Unlit notification indicator must be absent");
                bar.hoverExpanded = true;
                break;
            case 1:
                test.check(bar.pillState === "expanded" && pill.width > bar.compactWidth && pill.height === 40, "Hover expansion");
                test.check(bar.workspaceInset === 20, "Workspaces must stay at the left inset");
                test.check(test.findItem(bar.contentItem, item => item.text === Qt.formatDateTime(test.app.clock.date, "MM.dd")).opacity === 1, "Expanded date is missing");
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
                const networkPane = bar.activePane;
                test.app.toggle("bluetooth");
                test.check(networkPane.parent.opacity === 0, "Replaced content remained visible while taking the next view's size");
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
                bar.hoverExpanded = true;
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {fullscreen: true});
                break;
            case 16:
                test.check(bar.pillState === "hidden" && bar.mask.regions.length === 0 && bar.WlrLayershell.keyboardFocus === WlrKeyboardFocus.None, "Fullscreen must hide and release all input");
                test.check(test.findItem(bar.contentItem, item => item.objectName === "floatingPill").opacity === 0 && !bar.hoverExpanded, "Fullscreen must hide pill pixels and clear hover expansion");
                test.app.gesture("show", "50");
                test.check(bar.pillState === "hidden", "Super release must not reveal the pill over fullscreen");
                test.app.gesture("hide", "60");
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {fullscreen: false});
                test.check(bar.pillState === "hidden", "Exiting fullscreen must respect a held Super");
                test.app.gesture("show", "70");
                break;
            case 17:
                test.check(bar.pillState === "compact" && bar.mask.regions.length === 1, "Exiting fullscreen and releasing Super restores the pill");
                test.app.gesture("hide", "80");
                test.app.gesture("visibility", "90");
                test.app.gesture("show", "100");
                break;
            case 18:
                test.check(bar.pillState === "hidden" && !test.app.pillHidden && test.app.pillSuppressed && bar.mask.regions.length === 0, "Visibility shortcut must stay hidden after releasing Super");
                test.app.gesture("hide", "110");
                test.app.gesture("show", "120");
                test.check(bar.pillState === "hidden", "Super hold/release must preserve manual hiding");
                test.app.gesture("tap", "130");
                break;
            case 19:
                test.check(bar.pillState === "launcher" && test.app.pillSuppressed && bar.mask.regions.length === 1 && bar.wantsFocusGrab, "Super tap must open an interactive launcher while manually hidden");
                test.check(bar.WlrLayershell.keyboardFocus === WlrKeyboardFocus.OnDemand && test.findItem(bar.contentItem, item => item.objectName === "floatingPill").opacity === 1, "Hidden-pill launcher must paint and accept keyboard input");
                test.app.gesture("hide", "140");
                test.check(bar.pillState === "hidden" && bar.mask.regions.length === 0, "Holding Super must still hide the open launcher");
                test.app.gesture("show", "150");
                break;
            case 20:
                test.check(bar.pillState === "launcher", "Release must restore the launcher while manually hidden");
                test.app.gesture("tap", "160");
                break;
            case 21:
                test.check(bar.pillState === "hidden" && test.app.pillSuppressed && bar.mask.regions.length === 0 && !bar.wantsFocusGrab, "Second tap must close the launcher and preserve manual hiding");
                test.app.gesture("launcher", "170");
                break;
            case 22:
                test.check(bar.pillState === "launcher", "Explicit launcher shortcut must also work while manually hidden");
                bar.lostFocus();
                break;
            case 23:
                test.check(bar.pillState === "hidden" && test.app.pillSuppressed && bar.mask.regions.length === 0, "Focus dismissal must restore manual hiding");
                test.app.gesture("visibility", "180");
                break;
            case 24:
                test.check(bar.pillState === "compact" && bar.mask.regions.length === 1, "Second visibility shortcut must restore the pill");
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {fullscreen: true});
                test.app.gesture("tap", "190");
                break;
            case 25:
                test.check(bar.pillState === "launcher" && bar.wantsFocusGrab && bar.mask.regions.length === 1, "Super must open an interactive launcher over fullscreen");
                test.app.gesture("tap", "200");
                break;
            case 26:
                test.check(bar.pillState === "hidden" && bar.mask.regions.length === 0 && bar.WlrLayershell.keyboardFocus === WlrKeyboardFocus.None, "Closing the launcher must restore fullscreen hiding and release input");
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {fullscreen: false});
                break;
            case 27:
                test.check(bar.pillState === "compact", "Leaving fullscreen must restore the idle pill");
                test.check(test.hiddenLauncherFrames > 10, "Hidden-pill launcher transitions were not sampled");
                test.check(test.hiddenOpeningFrames >= 2 && test.hiddenClosingFrames >= 2,
                    "Hidden-pill launcher must animate both opening and closing");
                test.check(test.hiddenSlidingFrames >= 2, "Hidden-pill launcher must slide during its fade");
                console.warn("PILL PASS: stationary clock, frozen closing content, fixed radius/left inset, hidden inactive indicator, hover date, launcher search/launch, menu switching, holds, timestamp wraparound, fullscreen hide/restore, and interactive launcher access without a compact-pill flash while manually hidden or fullscreen");
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
            if (test.app.pillSuppressed || bar.fullscreen) {
                const body = test.findItem(bar.contentItem, item => item.objectName === "floatingPill");
                if (body.opacity > 0 && !test.app.pillHidden) {
                    test.hiddenLauncherFrames++;
                    test.check(bar.pillGeometry.height === bar.targetHeight && bar.pillGeometry.width === bar.targetWidth,
                        "Hidden-pill launcher flashed compact geometry: " + bar.pillGeometry);
                    const header = test.findItem(bar.contentItem, item => item.objectName === "pillHeader");
                    test.check(!header.visible || header.opacity === 0,
                        "Hidden-pill launcher revealed the idle header: step=" + test.step + ", reveal=" + body.opacity);
                    if (body.opacity < 1) {
                        if (test.app.panel) test.hiddenOpeningFrames++;
                        else test.hiddenClosingFrames++;
                        if (body.mapToItem(bar.contentItem, 0, 0).y < body.y) test.hiddenSlidingFrames++;
                    }
                }
            }
            if (test.watchClosing && bar.activePane) {
                test.closingFrames++;
                test.check(bar.paneGeometry === test.closingGeometry, "Closing content was resized or moved");
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: test.check(false, "Timed out"); }
}
