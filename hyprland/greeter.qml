import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Greetd
import Quickshell.Wayland
import "config/shell" as Desktop

ShellRoot {
    id: root

    readonly property string wallpaper: Quickshell.env("DOTFILES_GREETER_WALLPAPER")
    readonly property string preferredOutput: Quickshell.env("DOTFILES_GREETER_OUTPUT")
    readonly property var mainScreen: Quickshell.screens.find(screen => screen.name === preferredOutput)
                                      || Quickshell.screens[0]
    property string account: Quickshell.env("DOTFILES_GREETER_USER").trim()
    property bool choosingAccount: account.length === 0
    property bool waiting: false
    property bool responseRequired: false
    property bool echoResponse: false
    property string prompt: "Password"
    property string notice: ""
    property bool noticeIsError: false
    signal resetEntry()

    function begin() {
        if (choosingAccount || waiting || responseRequired) return;
        if (!Greetd.available) {
            noticeIsError = true;
            notice = "The login service is unavailable.";
            return;
        }
        if (Greetd.state !== GreetdState.Inactive) return;
        waiting = true;
        Greetd.createSession(account);
    }

    function chooseAccount() {
        choosingAccount = true;
        waiting = false;
        responseRequired = false;
        notice = "";
        if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession();
        resetEntry();
    }

    function submit(value) {
        if (waiting) return;
        notice = "";
        if (choosingAccount) {
            const username = value.trim();
            if (!username) return;
            account = username;
            choosingAccount = false;
            begin();
        } else if (responseRequired) {
            responseRequired = false;
            waiting = true;
            Greetd.respond(value);
        } else {
            begin();
        }
        resetEntry();
    }

    Desktop.PillTheme { id: pillColors }
    SystemClock { id: clock; precision: SystemClock.Minutes }

    Connections {
        target: Greetd

        function onAuthMessage(message, isError, needsResponse, echo) {
            if (root.choosingAccount) return;
            if (needsResponse) {
                root.waiting = false;
                root.responseRequired = true;
                root.echoResponse = echo;
                root.prompt = message.trim().replace(/:\s*$/, "") || "Password";
                root.resetEntry();
            } else if (message.trim()) {
                root.noticeIsError = isError;
                root.notice = message.trim();
            }
        }

        function onAuthFailure(message) {
            if (root.choosingAccount) return;
            root.waiting = false;
            root.responseRequired = false;
            root.noticeIsError = true;
            root.notice = message.trim() || "Authentication failed. Try again.";
            root.resetEntry();
        }

        function onError(message) {
            if (root.choosingAccount) return;
            root.waiting = false;
            root.responseRequired = false;
            root.noticeIsError = true;
            root.notice = message.trim() || "Unable to sign in. Try again.";
            root.resetEntry();
        }

        function onReadyToLaunch() {
            if (root.choosingAccount) {
                Greetd.cancelSession();
                return;
            }
            Greetd.launch(["/usr/bin/uwsm", "start", "-e", "-D", "Hyprland", "hyprland.desktop"]);
        }
    }

    Component.onCompleted: begin()

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: background

            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.namespace: "dotfiles-greeter-background"
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: "#342b27" }
                    GradientStop { position: 1; color: "#171513" }
                }
            }
            Image {
                anchors.fill: parent
                source: root.wallpaper ? "file://" + root.wallpaper : ""
                sourceSize.width: Math.round(background.width * (background.screen.devicePixelRatio || 1))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                clip: true
            }
            Rectangle {
                anchors.fill: parent
                color: "#420e0b0a"
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(16, Math.round(parent.height / 2 - height - Math.min(42, parent.height * 0.08)))
                spacing: 4
                visible: background.screen === root.mainScreen

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(clock.date, "HH:mm")
                    color: pillColors.text
                    font.family: pillColors.fontFamily
                    font.pixelSize: Math.max(52, Math.min(96, Math.round(background.height * 0.105)))
                    font.weight: Font.DemiBold
                    font.letterSpacing: -3
                    font.features: ({ "tnum": 1 })
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(clock.date, "dddd, MMMM d")
                    color: pillColors.secondary
                    font: pillColors.textFont
                }
            }
        }
    }

    PanelWindow {
        id: login

        screen: root.mainScreen
        visible: !!root.mainScreen
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "dotfiles-greeter-login"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Item {
            id: pill

            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height / 2 + Math.min(26, parent.height * 0.06))
            width: Math.min(412, parent.width - 36)
            height: form.implicitHeight + 12

            Desktop.PillBackground {
                anchors.fill: parent
                theme: pillColors
            }

            ColumnLayout {
                id: form

                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 6 }
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    TextField {
                        id: entry

                        Layout.fillWidth: true
                        implicitHeight: 36
                        readOnly: root.waiting || (!root.choosingAccount && !root.responseRequired)
                        placeholderText: root.choosingAccount ? "Username"
                            : root.waiting ? "Signing in…"
                            : root.responseRequired ? root.prompt : "Press Enter to retry"
                        placeholderTextColor: pillColors.secondary
                        color: pillColors.text
                        font: pillColors.textFont
                        leftPadding: 50
                        rightPadding: 16
                        echoMode: root.choosingAccount || root.echoResponse ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        inputMethodHints: echoMode === TextInput.Password
                            ? Qt.ImhHiddenText | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData : Qt.ImhNone
                        Accessible.name: placeholderText
                        Keys.onReturnPressed: root.submit(text)
                        Keys.onEnterPressed: root.submit(text)
                        background: Item {}

                        Desktop.ShellIcon {
                            x: 13
                            anchors.verticalCenter: parent.verticalCenter
                            name: "lock-keyhole"
                            width: 24
                            height: 24
                            opacity: 0.8
                        }
                    }

                    Button {
                        id: accountButton

                        visible: !root.choosingAccount
                        enabled: !root.waiting
                        implicitHeight: 36
                        Layout.maximumWidth: Math.floor(pill.width * 0.42)
                        leftPadding: 4
                        rightPadding: 14
                        Accessible.name: "Use another account"
                        onClicked: root.chooseAccount()
                        background: Item {}

                        contentItem: RowLayout {
                            spacing: 8
                            opacity: accountButton.hovered || accountButton.visualFocus ? 1 : 0.75

                            Text {
                                Layout.fillWidth: true
                                text: root.account
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: pillColors.text
                                font: pillColors.textFont
                            }
                            Desktop.ShellIcon {
                                name: "chevron-down"
                                Layout.preferredWidth: 14
                                Layout.preferredHeight: 14
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 50
                    Layout.rightMargin: 16
                    visible: root.notice.length > 0
                    text: root.notice
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    font: pillColors.textFont
                    color: root.noticeIsError ? pillColors.red : pillColors.secondary
                }
            }
        }

        Connections {
            target: root

            function onResetEntry() {
                entry.clear();
                Qt.callLater(() => entry.forceActiveFocus());
            }
        }

        Component.onCompleted: root.resetEntry()
        Component.onDestruction: entry.clear()
    }
}
