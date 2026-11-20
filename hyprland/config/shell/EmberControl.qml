import QtQuick

EmberSlot {
    id: root
    required property Item control
    shell: null
    ember: {
        if (shell) return null;
        // Each surface exposes its moving shape to the controls inside it.
        for (let item = control; item; item = item.parent) {
            if (item.controlEmber) return item.controlEmber;
        }
        return null;
    }
    shapeOpacity: 0.42
    property bool trackHover: true
    property Item registeredEmber: null
    readonly property bool pointerInside: visible && enabled && hover.hovered
    readonly property bool keyboardFocused: visible && enabled && !!control?.activeFocus

    function updateRegistration() {
        if (registeredEmber) {
            registeredEmber.follow(root, false, false);
            registeredEmber.follow(root, false, true);
        }
        registeredEmber = shell ? null : ember;
        if (pointerInside) registeredEmber?.follow(root, true, false);
        if (keyboardFocused) registeredEmber?.follow(root, true, true);
    }
    onEmberChanged: updateRegistration()
    onShellChanged: updateRegistration()
    onPointerInsideChanged: registeredEmber?.follow(root, pointerInside, false)
    onKeyboardFocusedChanged: registeredEmber?.follow(root, keyboardFocused, true)
    Component.onCompleted: updateRegistration()
    HoverHandler {
        id: hover
        parent: root.control
        enabled: root.trackHover && !!root.registeredEmber && root.visible && root.enabled
    }
}
