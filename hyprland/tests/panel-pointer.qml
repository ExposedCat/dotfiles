import QtQuick
import Quickshell

// Click the fixture's panel button on the isolated desktop. The test verifies
// pointer ownership on a persistent native panel, without user services.
Scope {
    id: test
    property var button
    property var indicator
    property bool opened: false
    property bool armed: false
    property int exits: 0
    function check(condition, message) {
        if (!condition) { console.error("PANEL POINTER FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function component(name) {
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/" + name + ".qml");
        check(c.status === Component.Ready, c.errorString()); return c;
    }
    PanelWindow {
        id: bar
        visible: true
        anchors { top: true; left: true; right: true }
        implicitHeight: 200
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        focusable: false
        Region { id: buttonInput; item: test.button }
        Region { id: bubbleInput; item: test.indicator ? test.indicator.bubbleItem : null }
        Region { id: popupInput; item: bar.contentItem }
        mask: Region { regions: test.opened ? [popupInput] : [buttonInput, bubbleInput] }
    }
    Item {
        id: popup
        parent: bar.contentItem
        visible: test.opened
        width: bar.width; height: 200
        Rectangle { x: 100; width: 120; height: 30; color: "black" }
        Rectangle { x: 100; y: 38; width: 280; height: 150; color: "black"; radius: 24 }
    }
    Component.onCompleted: {
        component("Dialogs");
        const theme = component("ShellTheme").createObject(test);
        button = component("PanelDrop").createObject(bar.contentItem, {x: 100, width: 120, theme: theme, text: "Popup"});
        indicator = component("NotificationIndicator").createObject(bar.contentItem,
            {x: 350, sourceWidth: 200, sourceRight: 176, theme: theme, present: true});
        check(popup.Window.window === button.Window.window, "Popup does not share the native panel surface");
        button.clicked.connect(() => { armed = true; opened = true; verifyOpen.start(); });
        button.hoveredChanged.connect(() => { if (armed && !button.hovered) exits++; });
        console.warn("PANEL POINTER READY: click the panel button");
    }
    Timer {
        id: verifyOpen; interval: 250
        onTriggered: {
            check(button.hovered && exits === 0, "Opening the popup transferred the pointer off the panel button (hovered=" + button.hovered + ", exits=" + exits + ")");
            check(indicator.bubbleItem.color.toString() === "#ffffff", "Notification bubble is not solid white");
            check(indicator.bubbleItem.x - indicator.sourceRight === 17, "Visible bubble gap was not halved from 34px");
            opened = false; indicator.present = false; verifyClose.start();
        }
    }
    Timer {
        id: verifyClose; interval: 250
        onTriggered: {
            check(button.hovered && exits === 0, "Closing the popup transferred the pointer off the panel button");
            check(!indicator.bubbleItem.visible && indicator.bubbleItem.x + indicator.bubbleItem.width <= indicator.sourceRight,
                  "White bubble did not slide completely behind the clock");
            armed = false;
            console.warn("PANEL POINTER PASS: no pointer handoff on popup open/close; solid white bubble, half gap, hidden retreat");
            Qt.quit();
        }
    }
    Timer { interval: 60000; running: true; onTriggered: test.check(false, "Timed out waiting for the isolated panel click"); }
}
