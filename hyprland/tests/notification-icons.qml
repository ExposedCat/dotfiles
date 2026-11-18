//@ pragma IconTheme MacTahoe-blue
import QtQuick
import Quickshell

// Run through isolated-gui with DOTFILES_SHELL_SOURCE and private XDG state.
Scope {
    id: test
    property var cards: []
    property var banner
    property var image
    property var store: ({live: {}, replying: {}, removing: {}, drafts: {}, replyErrors: {}, hoverPopup: () => {}})
    function check(condition, message) {
        if (!condition) { console.error("ICON REGRESSION FAIL:", message); Qt.exit(1); throw Error(message); }
    }
    function component(name) {
        const c = Qt.createComponent("file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/" + name + ".qml");
        check(c.status === Component.Ready, c.errorString());
        return c;
    }
    function named(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = named(child, name);
            if (found) return found;
        }
        return null;
    }
    FloatingWindow {
        id: window
        title: "Notification icon regression"
        implicitWidth: 620; implicitHeight: 440
        color: "#303030"; visible: true
        Item {
            id: previewContent; anchors.fill: parent
            Column { id: content; x: 30; y: 24; width: 560; spacing: 16 }
        }
    }
    Component.onCompleted: {
        check(!!Quickshell.env("ISOLATED_GUI_SESSION"), "Private desktop required");
        check(Quickshell.hasThemeIcon("drive-harddisk-usb-symbolic"), "USB drive icon is unavailable in the configured theme");
        const theme = component("PillTheme").createObject(test);
        component("LauncherResult");
        component("../tools/launcher");
        const card = component("NotificationCard");
        const entries = [
            {id: "usb", summary: "Kingston DataTraveler 2.0 can be safely unplugged", body: "Device can be removed.", image: "image://icon/drive-harddisk-usb-symbolic", icon: "org.gnome.Nautilus"},
            {id: "missing", summary: "Unavailable icon", body: "Hide unavailable notification images.", image: "image://icon/dotfiles-nonexistent-icon", icon: "dotfiles-nonexistent-icon"},
            {id: "file", summary: "File image", body: "Keep file images and their original crop behavior.", image: Quickshell.env("DOTFILES_SHELL_SOURCE") + "/icons/bell.svg", icon: "/dotfiles-nonexistent-icon.png"}
        ];
        cards = entries.map(entry => card.createObject(content, {theme: theme, store: test.store, entry: entry, inCenter: true, width: 560, height: Qt.binding(function() { return this.implicitHeight; })}));
        banner = card.createObject(content, {theme: theme, store: test.store, entry: entries[0], width: 560, height: Qt.binding(function() { return this.implicitHeight; })});
        image = component("SystemImage").createObject(window.contentItem, {iconSource: "drive-harddisk-usb-symbolic", width: 24, height: 24});
        tick.start();
    }
    Timer {
        id: tick; interval: 500
        property int phase: 0
        onTriggered: {
            const usb = test.named(cards[0], "notificationImage");
            const missing = test.named(cards[1], "notificationImage");
            const file = test.named(cards[2], "notificationImage");
            if (phase++ === 0) {
                check(usb.status === Image.Ready && usb.visible, "USB notification image did not render");
                check(usb.source.toString() === Quickshell.iconPath("drive-harddisk-usb-symbolic", true), "USB icon was replaced with a generic fallback");
                check(usb.fillMode === Image.PreserveAspectFit, "Device icon was cropped");
                check(usb.layer.enabled && usb.symbolicColor.toString() === "#ffffff", "Symbolic icon did not receive the card foreground color");
                check(missing.source.toString() === "" && !missing.visible, "Missing image provider icon reached the renderer");
                check(file.status === Image.Ready && file.fillMode === Image.PreserveAspectCrop, "File image was lost or its crop mode changed");
                for (const card of cards) check(!test.named(card, "notificationAppIcon"), "Center card still creates an application icon");
                const bannerImage = test.named(test.banner, "notificationImage");
                check(bannerImage.status === Image.Ready, "Banner lost its notification image");
                check(bannerImage.width === 56 && bannerImage.height === 56, "Banner image did not render at 56 pixels");
                const imageCenter = bannerImage.mapToItem(test.banner, 0, bannerImage.height / 2);
                check(Math.abs(imageCenter.y - test.banner.height / 2) <= 0.5, "Banner image is off-center");
                check(!test.named(test.banner, "notificationAppIcon"), "Banner still creates an application icon");
                check(image.status === Image.Ready, "Plain theme icon name did not resolve");
                check(image.resolve("image://icon/dotfiles-nonexistent-icon?fallback=drive-harddisk-usb-symbolic") === usb.source.toString(), "Provider fallback was lost");
                check(image.resolve("image://icon//tmp/example.png") === "/tmp/example.png", "Absolute notification image path was lost");
                image.iconSource = "/dotfiles-nonexistent-icon.png";
                image.fallbackSource = "file:" + Quickshell.env("DOTFILES_SHELL_SOURCE") + "/icons/bell.svg";
                tick.restart();
            } else if (phase === 2) {
                check(image.primaryFailed && image.status === Image.Ready, "Broken file did not advance to the bundled fallback");
                image.iconSource = "drive-harddisk-usb-symbolic";
                tick.restart();
            } else {
                check(!image.primaryFailed && image.source.toString() === usb.source.toString(), "Icon did not recover after a source update");
                image.visible = false;
                const preview = Quickshell.env("DOTFILES_ICON_PREVIEW");
                if (preview) previewContent.grabToImage(result => { check(result.saveToFile(preview), "Could not save preview"); console.warn("ICON REGRESSION PASS: USB icon, provider URLs, missing icons, files, fallbacks, source recovery"); Qt.quit(); });
                else { console.warn("ICON REGRESSION PASS: USB icon, provider URLs, missing icons, files, fallbacks, source recovery"); Qt.quit(); }
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: test.check(false, "Timed out"); }
}
