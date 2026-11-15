import QtQuick
import QtQuick.Window
import Quickshell

Scope {
    id: test
    property var pane: null
    property int stage: 0
    property int attempts: 0
    property int mathIndex: 0
    property var mathCases: [
        ["25 * 2 eur", "€50"], ["25 eur / 4", "€6.25"],
        ["2 + 2) * 3", "12"], ["2 * (3 + 4", "14"],
        ["sqrt(81)", "9"], ["-2^2", "−4"],
        ["2 + 15 eur)", "€17"], ["(15 eur - 2) / 4", "€3.25"]
    ]
    QtObject {
        id: desktop
        property bool fixture: false
        property string panel: "launcher"
        property bool emberEnabled: false
        property var emberTarget: null
        property string helper: Quickshell.env("DOTFILES_SHELL_SOURCE") + "/../tools/desktop.py"
    }
    Window { visible: true; width: 560; height: 428; Item { id: content; anchors.fill: parent; anchors.margins: 16 } }
    function check(condition, message) { if (!condition) { console.error("BACKEND UI FAIL:", message); Qt.quit(); throw Error(message); } }
    function search(text) { pane.children.find(c => c.objectName === "pillSearch").text = text; attempts = 0; }
    Component.onCompleted: {
        const base = "file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/";
        const theme = Qt.createComponent(base + "PillTheme.qml").createObject(test);
        const component = Qt.createComponent(base + "LauncherPane.qml");
        check(component.status === Component.Ready, component.errorString());
        pane = component.createObject(content, {shell: desktop, theme: theme, width: Qt.binding(() => content.width), height: Qt.binding(() => content.height)});
        check(!!pane, "Could not create launcher"); search("100 usd"); poll.start();
    }
    Timer {
        id: poll; interval: 100; repeat: true
        onTriggered: {
            test.check(++test.attempts < 100, "Timed out awaiting provider results");
            if (test.pane.loading) return;
            if (test.stage === 0) {
                test.check(test.pane.results.filter(r => r.kind === "currency").length === 2, "Worker currency results did not reach the view");
                test.search("char greek small letter alpha"); test.stage++;
            } else if (test.stage === 1) {
                test.check(test.pane.results[0].value === "α", "Worker Unicode results did not reach the view");
                test.search("days between 2026-01-01 and 2026-02-01"); test.stage++;
            } else if (test.stage === 2) {
                test.check(test.pane.results[0].value === "31 days", "Worker dates did not reach the view");
                test.search(test.mathCases[0][0]); test.stage++;
            } else if (test.stage === 3) {
                const current = test.mathCases[test.mathIndex];
                test.check(test.pane.selected.value === current[1], "Engine result missing for " + current[0]);
                if (++test.mathIndex < test.mathCases.length) test.search(test.mathCases[test.mathIndex][0]);
                else { test.pane.act("copy"); test.stage++; }
            } else {
                test.check(test.pane.copied, "Real engine copy action failed");
                console.warn("BACKEND UI PASS: real QML Process/stdin/JSON worker, currency arithmetic, repaired parentheses, functions, copy, Unicode and dates"); Qt.quit();
            }
        }
    }
}
