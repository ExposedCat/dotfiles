import QtQuick
import Quickshell
import Quickshell.Io

// Native pointer regression; run notification-input.py through isolated-gui.
Scope {
    id: test
    property var store
    property var overlays
    property var theme
    property int clicks: 0
    property int actions: 0
    property int activations: 0
    property int serial: 0
    function all(item) {
        let result = [];
        for (const child of item.children || []) result = result.concat([child], all(child));
        return result;
    }
    function component(name) {
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/" + name + ".qml");
        if (c.status !== Component.Ready) throw Error(c.errorString());
        return c;
    }
    function receive(title) {
        const callbacks = {};
        const n = {id: ++serial, appName: "Input test", desktopEntry: "input-test", appIcon: "", image: "",
            summary: title, body: "The bottom of this notification must accept pointer input. ".repeat(8),
            expireTimeout: 0, urgency: 1, transient: false, hasInlineReply: true};
        n.actions = [{identifier: "default", text: "Open", invoke: () => test.activations++},
            {identifier: "archive", text: "Archive conversation", invoke: () => test.actions++}];
        for (const name of ["summary", "body", "appName", "appIcon", "image", "expireTimeout", "urgency", "transient"])
            n[name + "Changed"] = {connect: callback => { callbacks[name] = callback; }};
        n.closed = {connect: callback => { callbacks.closed = callback; }};
        n.expire = () => callbacks.closed(1); n.dismiss = () => callbacks.closed(2);
        store.receive(n);
    }
    function bounds(item) {
        const window = overlays.bannerWindow;
        const point = item.mapToItem(window.contentItem, 0, 0);
        return {x: fakeShell.mainScreen.width - window.width + point.x, y: theme.panelGap + point.y,
            width: item.width, height: item.height};
    }
    FloatingWindow {
        implicitWidth: 1280; implicitHeight: 800
        title: "Notification input observer"; visible: true; color: "#4d525c"
        MouseArea { anchors.fill: parent; onClicked: test.clicks++; }
    }
    QtObject {
        id: fakeShell
        property var mainScreen: Quickshell.screens[0]
        property var focusedScreen: mainScreen
        property var notifications: test.store
        property string panel: ""
        property var osd: ({visible: false, output: "", icon: "", title: "", valueText: "", level: 0, muted: false})
    }
    Component.onCompleted: {
        store = component("Notifications").createObject(test, {statePath: Quickshell.env("XDG_STATE_HOME") + "/notifications.json"});
        store.dnd = false;
        theme = component("ShellTheme").createObject(test);
        overlays = component("Overlays").createObject(test, {shell: fakeShell, theme: theme, showOsd: false});
        receive("Single notification");
    }
    IpcHandler {
        target: "notificationInputTest"
        function populate(): void {
            test.receive("Neighbor"); test.receive("Grouped notification"); test.receive("Grouped notification");
        }
        function quit(): void { Qt.quit(); }
        function state(): string {
            return JSON.stringify({clicks: test.clicks, actions: test.actions, activations: test.activations,
                replying: Object.keys(test.store.replying).length,
                frozen: test.store.bannerFrozen,
                banners: test.all(test.overlays.banners).filter(item => item.objectName.startsWith("banner:") && item.presented).map(banner => ({
                    title: banner.entry.summary, ready: banner.arrival === 1, expanded: banner.expanded, unfold: banner.unfold,
                    bounds: test.bounds(banner),
                    cards: test.all(banner).filter(item => item.objectName === "notification-banner-card").sort((a, b) => a.index - b.index).map(card => ({
                        bounds: test.bounds(card), hovered: card.hovered, composing: card.composing,
                        controls: test.all(card).filter(item => item.visible && item.emberSlot !== undefined &&
                            (item.text || item.objectName === "notificationGroupToggle")).map(item => ({
                                name: item.text || item.objectName, bounds: test.bounds(item)
                            }))
                    }))
                }))});
        }
    }
}
