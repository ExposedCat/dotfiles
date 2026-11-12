import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var entries: []
    property string error: ""
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("desktop.py").toString().replace(/^file:\/\//, ""))
    readonly property var matches: entries.filter(entry => entry.preview.toLowerCase().includes(search.text.toLowerCase()))

    function copySelected() {
        if (!copier.running && list.currentIndex >= 0 && list.currentIndex < matches.length) {
            copier.command = ["python3", helper, "clipboard-copy", matches[list.currentIndex].id];
            copier.running = true;
        }
    }

    Process {
        id: reader
        command: ["python3", root.helper, "clipboard-list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.entries = JSON.parse(text); }
                catch (e) { root.error = "Could not load clipboard history."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) root.error = "Could not load clipboard history."; } }
    }

    Process {
        id: copier
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) Qt.quit();
            else root.error = "Could not restore this clipboard entry.";
        }
    }

    FloatingWindow {
        id: window
        title: "Clipboard history"
        implicitWidth: 600
        implicitHeight: 460
        color: "#1e1e2e"
        onClosed: Qt.quit()

        Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            Text {
                text: "Clipboard history"
                color: "#cdd6f4"
                font.pixelSize: 23
                font.weight: Font.DemiBold
            }
            TextField {
                id: search
                Layout.fillWidth: true
                implicitHeight: 44
                focus: true
                color: "#cdd6f4"
                placeholderText: "Search copied text and images"
                placeholderTextColor: "#a6adc8"
                selectByMouse: true
                font.pixelSize: 15
                leftPadding: 12
                background: Rectangle {
                    color: "#313244"
                    radius: 10
                    border.color: search.activeFocus ? "#89b4fa" : "#45475a"
                }
                onTextChanged: list.currentIndex = 0
                Keys.onDownPressed: list.currentIndex = Math.min(list.currentIndex + 1, list.count - 1)
                Keys.onUpPressed: list.currentIndex = Math.max(list.currentIndex - 1, 0)
                onAccepted: root.copySelected()
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
                    height: 45
                    radius: 9
                    color: ListView.isCurrentItem ? "#45475a" : mouse.containsMouse ? "#313244" : "transparent"
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.preview
                        textFormat: Text.PlainText
                        color: "#cdd6f4"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { list.currentIndex = index; root.copySelected(); }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: root.error || (reader.running ? "Loading…" : root.entries.length ? "No matches" : "Nothing copied yet")
                    color: "#a6adc8"
                    font.pixelSize: 15
                }
            }
            Text {
                Layout.fillWidth: true
                text: root.error || "↑ ↓  Select     Enter  Copy     Esc  Close"
                color: root.error ? "#f38ba8" : "#a6adc8"
                font.pixelSize: 12
            }
        }
    }
}
