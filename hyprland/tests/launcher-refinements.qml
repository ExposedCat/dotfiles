import QtQuick
import Quickshell
import Quickshell.Io

// Run inside the isolated helper's nested Wayland compositor.
Scope {
    id: test
    property var app: null
    property var pane: null
    property var providers: null
    property int step: 0
    property rect initial
    property rect closingStart
    property bool closingMotion: false
    property int closingFrames: 0
    property bool preview: !!Quickshell.env("DOTFILES_LAUNCHER_PREVIEW")
    function check(value, message) { if (!value) { console.error("LAUNCHER REFINEMENT FAIL:", message); Qt.quit(); throw Error(message); } }
    function find(item, predicate) {
        if (predicate(item)) return item;
        for (const child of item.children || []) { const result = find(child, predicate); if (result) return result; }
        return null;
    }
    function search(text) { find(pane, c => c.objectName === "pillSearch").text = text; }
    function character() { return {id: "character:B7", kind: "character", name: "middle dot", description: "U+00B7", value: "·", glyph: "·"}; }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "Private fixture required");
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(c.status === Component.Ready, c.errorString()); app = c.createObject(test);
        check(!!app, "Shell could not be created");
        app.fixtureData = Object.assign({}, app.fixtureData, {apps: [
            {id: "libreoffice.desktop", name: "LibreOffice Writer", description: "middle dot", icon: "libreoffice-writer"}
        ], launcherResults: {"char middle dot": [character()]}});
        app.toggle("launcher"); advance.start();
    }
    Timer {
        id: advance; interval: 300; repeat: true
        onTriggered: {
            const bar = test.app.pill;
            switch (test.step++) {
            case 0:
                test.pane = bar.activePane;
                test.check(!!test.pane, "Launcher did not open");
                test.providers = test.pane.data.find(c => c.objectName === "launcherProviders");
                test.check(!!test.providers, "No provider store");
                test.check(!test.find(test.pane, c => ["Copy", "Reveal", "Browse", "Code point", "☆ Save", "All", "Bookmarks"].includes(c.text)), "Action labels or tabs remain");
                test.check(!!test.find(test.pane, c => c.objectName === "launcherDragHandle"), "No drag grip");
                test.search("middle dot"); break;
            case 1:
                test.check(test.pane.selected.kind === "app", "Expected the provisional application result");
                test.providers.response({id: test.providers.generation, section: "quick", results: [test.character()]}); break;
            case 2:
                test.check(test.pane.selected.id === "character:B7", "Late character result did not become the first selection");
                test.pane.moveSelection(1);
                test.providers.response({id: test.providers.generation, section: "files", results: [{id:"file:fixture", kind:"file", name:"File", description:"Fixture"}]}); break;
            case 3:
                test.check(test.pane.selected.appId === "libreoffice.desktop", "Late results displaced deliberate keyboard selection");
                test.search("char middle dot"); break;
            case 4:
                test.check(test.pane.selected.id === "character:B7", "Typing a new query did not reset selection");
                test.initial = bar.pillGeometry;
                if (test.preview) { advance.stop(); return; }
                bar.beginLauncherDrag(100, 100); bar.moveLauncherDrag(102, 101);
                test.check(!bar.launcherDragged, "Press or tiny movement pinned the launcher");
                bar.moveLauncherDrag(1100, 900);
                test.check(bar.dragPressed && bar.wantsFocusGrab && bar.mask.regions[0].item === bar.contentItem,
                           "Fast drag released the full native input region or focus grab");
                bar.lostFocus(); test.check(test.app.panel === "launcher", "Focus loss interrupted the active pointer gesture");
                bar.moveLauncherDrag(260, 220); bar.endLauncherDrag(); break;
            case 5:
                test.check(bar.launcherDragged && bar.pillGeometry.x === test.initial.x + 160 && bar.pillGeometry.y === test.initial.y + 120, "Grip movement did not move the launcher");
                test.check(bar.mask.regions.length === 1 && bar.mask.regions[0].item.objectName === "floatingPill", "Dragged launcher intercepts outside clicks");
                bar.lostFocus(); test.check(test.app.panel === "launcher", "Dragged launcher dismissed on focus loss");
                test.pane.act("copy"); test.check(test.app.panel === "launcher", "Copy dismissed dragged launcher");
                test.closingStart = bar.pillGeometry; test.closingMotion = true;
                bar.dismiss();
                test.check(bar.pillGeometry === test.closingStart, "Closing snapped the moved launcher before its animation");
                break;
            case 6:
                test.closingMotion = false;
                test.check(test.closingFrames >= 2, "Closing did not animate the position and size together");
                test.check(!bar.launcherDragged && bar.pillGeometry.y === bar.theme.panelGap, "Closing did not reset dragged placement");
                test.app.toggle("launcher"); break;
            case 7:
                test.check(!bar.launcherDragged, "New launcher retained pin state");
                test.check(test.find(test.pane, c => c.objectName === "pillSearch").text === "" && test.providers.query === "",
                           "Reopening retained the previous search input");
                bar.hoverExpanded = true;
                bar.lostFocus(); test.check(test.app.panel === "" && bar.pillState === "compact", "Ordinary launcher did not collapse on focus loss");
                test.app.toggle("bluetooth"); break;
            case 8:
                bar.lostFocus(); test.check(test.app.panel === "", "Ordinary pill view did not dismiss on focus loss");
                console.warn("LAUNCHER REFINEMENT PASS: plain rows, first async result, deliberate navigation, drag threshold/position, pinned focus loss, reset, normal dismissal"); Qt.quit();
            }
        }
    }
    Timer {
        interval: 16; repeat: true; running: test.closingMotion
        onTriggered: {
            const bar = test.app.pill, g = bar.pillGeometry;
            if (g.height > bar.headerHeight && g.height < test.closingStart.height
                && g.y > bar.theme.panelGap && g.y < test.closingStart.y) test.closingFrames++;
        }
    }
    IpcHandler {
        target: "launcherTest"
        function state(): string {
            const bar = test.app.pill;
            return JSON.stringify({panel: test.app.panel, pressed: bar.dragPressed, dragged: bar.launcherDragged,
                geometry: bar.pillGeometry, query: test.pane ? test.find(test.pane, c => c.objectName === "pillSearch").text : ""});
        }
    }
    Timer { interval: 10000; running: !test.preview; onTriggered: test.check(false, "Timed out") }
}
