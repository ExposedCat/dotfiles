import QtQuick
import QtQuick.Window
import Quickshell

Scope {
    id: test
    property var pane: null
    property int step: 0
    property bool preview: !!Quickshell.env("DOTFILES_LAUNCHER_PREVIEW")
    QtObject {
        id: desktop
        property bool fixture: true
        property var fixtureData: ({apps: [
            {id: "terminal.desktop", name: "Terminal", description: "Command line", icon: "utilities-terminal"},
            {id: "telegram.desktop", name: "Telegram", description: "Messaging", icon: "org.telegram.desktop"},
            {id: "dev.desktop", name: "Dev", description: "Telephone and terminal tools"}
        ], launcherResults: {
            "12 * (3 + 4)": [{id: "calculation:12 * (3 + 4)", kind: "calculation", name: "84", value: "84"}],
            "100 usd": [
                {id: "currency:czk", kind: "currency", name: "2,100 CZK", description: "100 USD → CZK · Rates 2026-11-13", value: "2100 CZK"},
                {id: "currency:eur", kind: "currency", name: "86 EUR", description: "100 USD → EUR · Rates 2026-11-13", value: "86 EUR"}
            ],
            "char em dash": [{id: "character:2014", kind: "character", name: "em dash", description: "U+2014", value: "—", glyph: "—"}],
            "tele": [{id: "character:260E-FE0F", kind: "character", name: "telephone", description: "U+260E U+FE0F", value: "☎️", glyph: "☎️"}],
            "days between 2026-01-01 and 2026-02-01": [{id: "date:days", kind: "date", name: "31 days", description: "Calendar days · End date excluded", value: "31 days"}]
        }, launcherFiles: {"files invoice": [{id: "file:invoice", kind: "file", name: "Invoice November.pdf", description: "/home/example/Documents", path: "/home/example/Documents/invoice.pdf", uri: "file:///home/example/Documents/invoice.pdf", icon: "application-pdf"}]}})
        property string panel: "launcher"
        property bool emberEnabled: false
        property var emberTarget: null
        function fixtureEvent(name, data) { console.warn("FIXTURE", name, JSON.stringify(data)); }
    }
    Window {
        id: window
        visible: true; width: 560; height: 428; color: "#322923"
        title: "Launcher provider preview"
        Item { id: content; anchors.fill: parent; anchors.margins: 16 }
    }
    function check(condition, message) {
        if (!condition) { console.error("PROVIDER UI FAIL:", message); Qt.quit(); throw Error(message); }
    }
    function search(text) { test.pane.children.find(c => c.objectName === "pillSearch").text = text; }
    Component.onCompleted: {
        const base = "file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/";
        const theme = Qt.createComponent(base + "PillTheme.qml");
        check(theme.status === Component.Ready, theme.errorString());
        const component = Qt.createComponent(base + "LauncherPane.qml");
        check(component.status === Component.Ready, component.errorString());
        pane = component.createObject(content, {shell: desktop, theme: theme.createObject(test),
            width: Qt.binding(() => content.width), height: Qt.binding(() => content.height)});
        check(!!pane, "Could not create launcher");
        search("100 usd");
        if (!preview) advance.start();
    }
    Timer {
        id: advance; interval: 120; repeat: true
        onTriggered: {
            switch (test.step++) {
            case 0:
                test.check(test.pane.results.length === 2 && test.pane.selected.kind === "currency", "Currency suggestions were not selectable");
                test.pane.act("favorite"); test.pane.act("copy");
                test.check(test.pane.copied, "Copy action did not report success");
                test.search("еудупкфь"); break;
            case 1:
                test.check(test.pane.results[0].appId === "telegram.desktop", "Wrong-layout application search failed");
                test.search("char em dash"); break;
            case 2:
                test.check(test.pane.results[0].glyph === "—", "Character filter failed");
                test.search("files invoice"); break;
            case 3:
                test.check(test.pane.results.length === 1 && test.pane.selected.kind === "file", "File results were not merged");
                test.pane.act("reveal");
                test.check(desktop.panel === "", "Reveal did not close the launcher");
                desktop.panel = "launcher";
                test.search("12 * (3 + 4)"); break;
            case 4:
                test.check(test.pane.results[0].value === "84", "Engine result was not selectable");
                test.pane.act("copy"); test.check(test.pane.copied, "Arithmetic copy failed");
                test.search("days between 2026-01-01 and 2026-02-01"); break;
            case 5:
                test.check(test.pane.results[0].value === "31 days", "Date result failed");
                test.search("tele"); break;
            case 6:
                test.check(test.pane.results[0].appId === "telegram.desktop" && test.pane.selected.appId === "telegram.desktop", "Title match did not lead provider results");
                test.check(test.pane.results.findIndex(r => r.kind === "character") < test.pane.results.findIndex(r => r.appId === "dev.desktop"), "Description-only app match was promoted ahead of character results");
                console.warn("PROVIDER UI PASS: currencies, layout recovery, characters, files, contextual actions, dates, arithmetic");
                Qt.quit();
            }
        }
    }
}
