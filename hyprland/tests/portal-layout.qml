import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
Scope {
    id: test
    property var portal: null
    property bool checked: false
    TestResult { id: objects }
    function check(value, message) { if (!value) throw Error(message); }
    Component.onCompleted: {
        const component = Qt.createComponent("file:" + Quickshell.env("DOTFILES_PORTAL_SOURCE") + "/portal.qml");
        check(component.status === Component.Ready, component.errorString());
        portal = component.createObject(test);
    }
    Timer {
        interval: 500; running: true
        onTriggered: {
            check(test.portal.ready, "Portal request did not load");
            test.portal.choose(test.portal.data.outputs[0].id);
            settle.start();
        }
    }
    Timer {
        id: settle; interval: 400
        onTriggered: {
            const tabs = objects.findChild(test.portal, "shareTabs");
            const grid = objects.findChild(test.portal, "shareSources");
            const label = grid?.itemAtIndex(0)?.children.find(child => child.objectName === "shareSourceName");
            const fullName = objects.findChild(test.portal, "shareSelectedName");
            console.warn("Sharing controls", !!tabs, !!grid, !!label, !!fullName);
            check(tabs && grid && label && fullName, "Sharing controls are missing");
            check(tabs.width / 3 > 140, "Sharing tabs are too narrow");
            check(label.x >= 0 && label.x + label.width <= label.parent.width, "Source name extends beyond its card");
            check(label.y + label.height <= label.parent.height, "Source name is clipped vertically");
            check(grid.height >= grid.cellHeight, "Grid clips the first row of source names");
            check(fullName.visible && fullName.height >= fullName.contentHeight, "Complete selected source name is clipped");
            test.checked = true;
            console.warn("PORTAL LAYOUT PASS: readable tab widths, unclipped source name, complete selected name, and full first row");
        }
    }
    IpcHandler { target: "portalLayoutTest"; function state(): bool { return test.checked; } }
}
