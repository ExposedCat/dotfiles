import QtQuick

PortalDialog {
    required property var shell
    sharedEmber: shell.pill.ember
    requestData: shell.portal.data
    submitting: shell.portal.submitting
    onResponded: response => shell.portal.finishResponse(response)
    Component.onCompleted: activate()
}
