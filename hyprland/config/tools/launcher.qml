import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var apps: []
    property string error: ""
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("desktop.py").toString().replace(/^file:\/\//, ""))
    readonly property var matches: {
        const query = search.text.trim().toLowerCase();
        const tokens = query.split(/\s+/).filter(t => t.length);
        return apps.filter(app => {
            const haystack = (app.name + " " + app.description + " " + app.keywords.join(" ")).toLowerCase();
            return tokens.every(t => haystack.includes(t));
        }).sort((a, b) => {
            function rank(app) {
                const name = app.name.toLowerCase();
                return !query || name.startsWith(query) ? 0 : name.includes(query) ? 1 : 2;
            }
            return rank(a) - rank(b) || a.name.localeCompare(b.name);
        });
    }
    function launch() {
        if (!launchProcess.running && list.currentIndex >= 0 && list.currentIndex < matches.length) {
            launchProcess.command = ["python3", helper, "app-launch", matches[list.currentIndex].id];
            launchProcess.running = true;
        }
    }
    Process {
        id: loader
        command: ["python3", root.helper, "apps-list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.apps = JSON.parse(text); }
                catch(e) { root.error = "Could not load applications."; }
            }
        }
    }
    Process {
        id: launchProcess
        onExited: (code, status) => {
            if (code === 0) Qt.quit();
            else root.error = "Could not launch this application.";
        }
    }
    FloatingWindow {
        title: "Applications"
        implicitWidth: 620
        implicitHeight: 490
        color: "#1e1e2e"
        onClosed: Qt.quit()
        Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14
            Text { text: "Applications"; color: "#cdd6f4"; font.pixelSize: 23; font.weight: Font.DemiBold }
            TextField {
                id: search
                Layout.fillWidth: true
                implicitHeight: 46
                focus: true
                color: "#cdd6f4"
                placeholderText: "Type an application name…"
                placeholderTextColor: "#a6adc8"
                font.pixelSize: 16
                leftPadding: 12
                selectByMouse: true
                background: Rectangle { color: "#313244"; radius: 10; border.color: "#89b4fa" }
                onTextChanged: list.currentIndex = 0
                Keys.onDownPressed: list.currentIndex = Math.min(list.currentIndex + 1, list.count - 1)
                Keys.onUpPressed: list.currentIndex = Math.max(list.currentIndex - 1, 0)
                onAccepted: root.launch()
                Component.onCompleted: forceActiveFocus()
            }
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 5
                model: root.matches
                currentIndex: 0
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 58
                    radius: 10
                    color: ListView.isCurrentItem ? "#45475a" : mouse.containsMouse ? "#313244" : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12
                        Image {
                            Layout.preferredWidth: 32; Layout.preferredHeight: 32
                            source: modelData.icon ? (modelData.icon.startsWith("/") ? "file://" + modelData.icon : Quickshell.iconPath(modelData.icon)) : ""
                            sourceSize.width: 32; sourceSize.height: 32
                            fillMode: Image.PreserveAspectFit
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { Layout.fillWidth: true; text: modelData.name; textFormat: Text.PlainText; color: "#cdd6f4"; font.pixelSize: 16; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: modelData.description; textFormat: Text.PlainText; color: "#a6adc8"; font.pixelSize: 11; elide: Text.ElideRight }
                        }
                    }
                    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: { list.currentIndex = index; root.launch(); } }
                }
                Text { anchors.centerIn: parent; visible: list.count === 0; text: loader.running ? "Loading…" : "No applications found"; color: "#a6adc8" }
            }
            Text { text: root.error || "↑ ↓  Select     Enter  Launch     Esc  Close"; color: root.error ? "#f38ba8" : "#a6adc8"; font.pixelSize: 12 }
        }
    }
}
