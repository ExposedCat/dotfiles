import QtQuick
import Quickshell

// Run with two HEADLESS outputs and a private fixture through isolated-gui.
Scope {
    id: test
    property var app: null
    property int step: 0
    property real clockX: 0
    function check(value, message) {
        if (!value) { console.error("WORKSPACE FEEDBACK FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function find(item, predicate) {
        if (predicate(item)) return item;
        for (const child of item.children || []) { const match = find(child, predicate); if (match) return match; }
        return null;
    }
    function clock() { return find(app.pill.contentItem, c => typeof c.text === "string" && /^\d\d:\d\d$/.test(c.text)); }
    Component.onCompleted: {
        check(!!Quickshell.env("DOTFILES_SHELL_FIXTURE"), "Private fixture required");
        check(Quickshell.screens.length === 2, "Two private outputs required");
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/shell.qml");
        check(component.status === Component.Ready, component.errorString());
        app = component.createObject(test);
    }
    Timer {
        interval: 350; repeat: true; running: !!test.app
        onTriggered: {
            const bar = test.app.pill;
            const wing = test.find(bar.contentItem, c => c.objectName === "workspaceWing");
            switch (test.step++) {
            case 0:
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {
                    mainOutput: "HEADLESS-1", focusedOutput: "HEADLESS-2",
                    workspacesByMonitor: {
                        "HEADLESS-1": [{id:1}, {id:2, active:true}, {id:3}],
                        "HEADLESS-2": [{id:4}, {id:5}, {id:6, active:true}, {id:7}]
                    }
                }); break;
            case 1:
                test.clockX = test.clock().mapToItem(bar.contentItem, 0, 0).x;
                test.app.osd.showWorkspace("Custom workspace name", "HEADLESS-2", "6"); break;
            case 2:
                test.check(bar.screen.name === "HEADLESS-1", "Workspace feedback moved the pill to another output");
                test.check(wing.spaces.map(w => w.id).join(",") === "4,5,6,7", "Secondary switch showed the main monitor's workspaces");
                test.check(wing.workspaceIndicator.current === 2, "Indicator used the display name instead of the switched workspace ID");
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {focusedOutput:"HEADLESS-1"}); break;
            case 3:
                test.check(bar.workspaceOutput === "HEADLESS-2", "A focus change retargeted feedback still being shown");
                bar.hoverExpanded = true; break;
            case 4:
                test.check(bar.spaces.map(w => w.id).join(",") === "1,2,3", "Expanded controls did not follow monitor focus");
                test.app.fixtureData = Object.assign({}, test.app.fixtureData, {focusedOutput:"HEADLESS-2"}); break;
            case 5:
                test.check(bar.spaces.map(w => w.id).join(",") === "4,5,6,7", "Expanded controls retained the main monitor's workspaces");
                bar.hoverExpanded = false;
                test.app.osd.showWorkspace("Another custom name", "HEADLESS-1", "2"); break;
            case 6:
                test.check(wing.spaces.length === 3 && wing.workspaceIndicator.current === 1, "Rapid cross-monitor feedback retained the previous list or selection");
                test.check(test.clock().mapToItem(bar.contentItem, 0, 0).x === test.clockX, "Cross-monitor feedback moved the clock");
                test.app.osd.showAudio(false, 0.5, false); break;
            case 7:
                test.check(bar.workspaceOutput === "HEADLESS-2", "Audio feedback retained a stale workspace output");
                console.warn("WORKSPACE FEEDBACK PASS: secondary list, stable identity, focused expanded controls, cross-monitor switches, stationary clock, audio reset");
                Qt.quit();
            }
        }
    }
    Timer { interval: 6000; running: true; onTriggered: test.check(false, "Timed out") }
}
