import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Widgets

ClippingRectangle {
    id: root
    required property var modelData
    required property int index
    required property var theme
    required property string helper
    required property bool fixture
    required property bool stillImage
    required property Item focusEmber
    readonly property alias emberSlot: focusSlot
    property bool previewVisible: false
    property bool remotePreviewRequested: false
    property bool selected: false
    property string thumbnail: modelData.thumbnail || ""
    readonly property string kind: modelData.kind
    readonly property bool remote: kind === "remote-image"
    readonly property bool mediaOutline: stillImage || kind === "video"
    readonly property bool staticFocus: selected && !focusSlot.occupied
    readonly property bool hasSource: stillImage && !!modelData.source
    readonly property bool previewable: remote || kind === "legacy-media" || !!modelData.mime && (stillImage || kind === "video")
    signal activated()

    radius: 10
    implicitHeight: richText.item?.implicitHeight ?? 44
    clip: true
    color: staticFocus && !mediaOutline ? Qt.tint(theme.surface, Qt.alpha(theme.focusColor, 0.42))
        : pointer.containsMouse ? Qt.alpha(theme.hover, 0.72) : theme.surface
    Accessible.role: Accessible.Button
    Accessible.name: modelData.preview || "Formatted text"
    Accessible.onPressAction: activated()

    EmberSlot {
        id: focusSlot
        shell: null
        ember: root.focusEmber
        anchors.fill: parent
        z: root.mediaOutline ? 1 : 0
        shapeRadius: root.radius
        shapeOpacity: root.mediaOutline ? 1 : 0.42
        shapeBorderWidth: root.mediaOutline ? 3 : 0
    }

    Process {
        running: root.previewable && !root.fixture && (!root.remote || root.remotePreviewRequested)
        command: [root.helper, "desktop", "clipboard-preview", root.modelData.id,
            root.remote ? "remote-image" : root.modelData.mime || ""]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text) return;
                try { root.thumbnail = JSON.parse(text); }
                catch (_) { root.thumbnail = ""; }
            }
        }
    }
    Timer {
        // The list can instantiate rows below the fold. Wait until the row is
        // on screen before requesting a remote preview.
        running: root.remote && root.previewVisible && !root.fixture && !root.remotePreviewRequested
        interval: 160
        onTriggered: root.remotePreviewRequested = true
    }

    Item {
        id: imagePreview
        visible: root.stillImage
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: root.height - sourceLine.height
        clip: true
        Image {
            id: cover
            objectName: "clipboardThumbnail"
            anchors.fill: parent
            source: root.stillImage ? root.thumbnail : ""
            fillMode: Image.PreserveAspectCrop
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignVCenter
            cache: false
        }
        SystemImage {
            anchors.centerIn: parent
            width: 30; height: width
            visible: cover.status !== Image.Ready && status === Image.Ready
            iconSource: "image-x-generic-symbolic"
            fallbackIcon: "image-x-generic"
            symbolicColor: root.theme.secondary
        }
    }

    RowLayout {
        id: sourceLine
        objectName: "clipboardImageSource"
        visible: root.hasSource
        anchors { top: imagePreview.bottom; left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12 }
        height: root.hasSource ? 32 : 0
        spacing: 7
        ShellIcon {
            name: "link"
            Layout.preferredWidth: 16; Layout.preferredHeight: 16
        }
        Text {
            Layout.fillWidth: true
            text: root.modelData.source || ""
            textFormat: Text.PlainText
            font: root.theme.textFont
            color: root.theme.secondary
            elide: Text.ElideRight
        }
    }

    Loader {
        id: richText
        anchors.fill: parent
        active: root.kind === "html"
        sourceComponent: ClipboardRichText { theme: root.theme; html: root.modelData.html }
    }

    Item {
        visible: !root.stillImage && root.kind !== "html"
        anchors.fill: parent
        anchors.margins: 10
        clip: true
        RowLayout {
            anchors.fill: parent
            spacing: 10
            Rectangle {
                Layout.preferredWidth: 25; Layout.preferredHeight: 25
                radius: 6
                visible: root.kind === "color"
                color: root.modelData.swatch || "transparent"
                border.color: Qt.alpha(root.theme.text, 0.34)
                border.width: 1
            }
            ShellIcon {
                visible: root.kind === "files" || root.kind === "video"
                name: root.kind === "video" ? "play" : "clipboard"
                Layout.preferredHeight: 19; Layout.preferredWidth: 19
            }
            Image {
                visible: root.kind === "video" && root.thumbnail.length > 0
                Layout.preferredWidth: Math.min(210, parent.width * 0.65)
                Layout.fillHeight: true
                source: visible ? root.thumbnail : ""
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                cache: false
            }
            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumHeight: parent.height
                text: root.modelData.preview
                textFormat: Text.PlainText
                font: root.theme.textFont
                color: root.kind === "link" ? root.theme.amber : root.theme.text
                wrapMode: Text.WrapAnywhere
                maximumLineCount: root.kind === "link" || root.kind === "text" ? 1 : 2
                elide: Text.ElideRight
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        visible: !root.mediaOutline || !focusSlot.occupied
        border.color: root.staticFocus && root.mediaOutline
            ? root.theme.focusColor : Qt.alpha(root.theme.border, 0.20)
        border.width: root.staticFocus && root.mediaOutline ? focusSlot.shapeBorderWidth : 1
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
