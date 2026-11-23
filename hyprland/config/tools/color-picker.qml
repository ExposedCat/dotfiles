import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string directory: Quickshell.env("DOTFILES_CAPTURE_SESSION")
    property var outputs: []
    readonly property var screens: Quickshell.screens.filter(screen => outputs.some(output => output.name === screen.name))
    readonly property var keyboardScreen: screens.find(screen => outputs.some(output => output.focused && output.name === screen.name)) || screens[0]

    FileView { id: session; path: root.directory ? root.directory + "/session.json" : ""; blockLoading: true }
    FileView {
        id: result
        path: root.directory ? root.directory + "/result.json" : ""
        preload: false
        blockWrites: true
        atomicWrites: true
    }

    Component.onCompleted: {
        try {
            outputs = JSON.parse(session.text()).outputs;
            if (!screens.length) throw new Error("No captured displays are available");
        } catch (error) {
            console.error("Could not open the color picker:", error);
            Qt.exit(1);
        }
    }

    Variants {
        model: root.screens
        PanelWindow {
            id: window
            required property ShellScreen modelData
            readonly property var output: root.outputs.find(output => output.name === modelData.name)

            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "dotfiles-color-picker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: modelData === root.keyboardScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Image {
                id: snapshot
                anchors.fill: parent
                source: window.output.plain
                fillMode: Image.Stretch
                onStatusChanged: {
                    if (status === Image.Error) Qt.exit(1);
                }
            }

            MouseArea {
                id: pointer
                anchors.fill: parent
                focus: true
                hoverEnabled: true
                cursorShape: Qt.CrossCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                // Convert logical surface coordinates to the snapshot's physical pixels.
                function pixel(position: real, extent: real, pixels: int): int {
                    return Math.max(0, Math.min(pixels - 1, Math.floor(position * pixels / extent)));
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) event.accepted = true;
                }
                Keys.onReleased: event => {
                    if (event.key !== Qt.Key_Escape) return;
                    event.accepted = true;
                    if (!event.isAutoRepeat) Qt.quit();
                }
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        if (snapshot.status !== Image.Ready) return;
                        result.setText(JSON.stringify({
                            output: window.output.name,
                            x: pixel(mouse.x, width, snapshot.sourceSize.width),
                            y: pixel(mouse.y, height, snapshot.sourceSize.height)
                        }));
                    }
                    Qt.quit();
                }
            }

            Canvas {
                id: lens
                readonly property int cell: 14
                readonly property int cells: 9
                readonly property int gap: 20
                readonly property int sampleX: pointer.pixel(pointer.mouseX, pointer.width, snapshot.sourceSize.width)
                readonly property int sampleY: pointer.pixel(pointer.mouseY, pointer.height, snapshot.sourceSize.height)

                visible: pointer.containsMouse && snapshot.status === Image.Ready
                width: cell * cells
                height: width
                x: Math.max(0, Math.min(window.width - width, pointer.mouseX + gap + width <= window.width
                                          ? pointer.mouseX + gap : pointer.mouseX - gap - width))
                y: Math.max(0, Math.min(window.height - height, pointer.mouseY + gap + height <= window.height
                                          ? pointer.mouseY + gap : pointer.mouseY - gap - height))
                smooth: false
                antialiasing: true

                onSampleXChanged: requestPaint()
                onSampleYChanged: requestPaint()
                onVisibleChanged: { if (visible) requestPaint(); }
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const center = width / 2;
                    const half = Math.floor(cells / 2);
                    const left = sampleX - half, top = sampleY - half;
                    const sx = Math.max(0, left), sy = Math.max(0, top);
                    const sw = Math.min(left + cells, snapshot.sourceSize.width) - sx;
                    const sh = Math.min(top + cells, snapshot.sourceSize.height) - sy;

                    ctx.save();
                    ctx.beginPath();
                    ctx.arc(center, center, center - 1, 0, 2 * Math.PI);
                    ctx.clip();
                    ctx.fillStyle = "#202020";
                    ctx.fillRect(0, 0, width, height);
                    if (sw > 0 && sh > 0)
                        ctx.drawImage(snapshot, sx, sy, sw, sh, (sx - left) * cell, (sy - top) * cell, sw * cell, sh * cell);
                    ctx.fillStyle = "#40000000";
                    for (let i = cell; i < width; i += cell) {
                        ctx.fillRect(i, 0, 1, height);
                        ctx.fillRect(0, i, width, 1);
                    }
                    ctx.restore();

                    ctx.strokeStyle = "#f5f5f5";
                    ctx.lineWidth = 2;
                    ctx.stroke();
                    const target = half * cell;
                    ctx.strokeStyle = "#181818";
                    ctx.lineWidth = 3;
                    ctx.strokeRect(target, target, cell, cell);
                    ctx.strokeStyle = "white";
                    ctx.lineWidth = 1;
                    ctx.strokeRect(target, target, cell, cell);
                }
            }
        }
    }
}
