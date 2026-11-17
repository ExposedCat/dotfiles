import QtQuick
import QtQuick.Effects
import Quickshell

// Notification image hints can already be image://icon URLs. Validate those
// too: the icon provider returns a checkerboard with Image.Ready on failure.
Image {
    id: root
    property string iconSource: ""
    property string fallbackIcon: ""
    property url fallbackSource: ""
    property color symbolicColor: "#ffffff"
    property bool primaryFailed: false
    property bool fallbackFailed: false
    readonly property string primarySource: resolve(iconSource)
    readonly property string themeFallback: resolve(fallbackIcon)
    function resolve(value) {
        if (!value) return "";
        if (value.startsWith("image://icon/")) {
            const request = value.slice("image://icon/".length);
            const split = request.indexOf("?");
            const name = split < 0 ? request : request.slice(0, split);
            if (name.startsWith("/")) return name;
            const themed = Quickshell.iconPath(name, true);
            if (themed) return themed;
            const option = split < 0 ? "" : request.slice(split + 1);
            if (option.startsWith("fallback=")) return Quickshell.iconPath(option.slice(9), true);
            if (option.startsWith("path=")) return "/" + option.slice(5) + "/" + name.slice(name.lastIndexOf("/") + 1);
            return "";
        }
        if (/^(file:|image:|\/)/.test(value)) return value;
        return Quickshell.iconPath(value, true);
    }
    onIconSourceChanged: primaryFailed = false
    onFallbackIconChanged: fallbackFailed = false
    source: (!primaryFailed && primarySource) || (!fallbackFailed && themeFallback) || fallbackSource
    onStatusChanged: {
        if (status !== Image.Error) return;
        const failedSource = source.toString();
        Qt.callLater(() => {
            if (status !== Image.Error || source.toString() !== failedSource) return;
            if (!primaryFailed && primarySource && failedSource === primarySource) primaryFailed = true;
            else if (!fallbackFailed && themeFallback && failedSource === themeFallback) fallbackFailed = true;
        });
    }
    visible: status === Image.Ready
    fillMode: Image.PreserveAspectFit
    layer.enabled: /-symbolic(?:\?|$)/.test(source.toString())
    // Flatten RGB to white before tinting; preserve the icon's alpha edges.
    layer.effect: MultiEffect { contrast: -1; brightness: 0.5; colorization: 1; colorizationColor: root.symbolicColor }
}
