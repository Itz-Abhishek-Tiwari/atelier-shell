import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings → Profile.
ColumnLayout {
    required property var win
    Layout.fillWidth: true
    spacing: 20
    onVisibleChanged: if (visible) Profile.refresh()

    // hero: picture + name + account, with the picture actions
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 148
        radius: Atelier.radiusMd
        color: Atelier.container
        border.width: 1
        border.color: Atelier.outline
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 22; anchors.rightMargin: 22
            spacing: 20
            Avatar {
                size: 104
                ring: true
                Rectangle {
                    anchors.right: parent.right; anchors.bottom: parent.bottom
                    width: 32; height: 32; radius: Atelier.radiusLg
                    color: Atelier.accentFill
                    border.width: 3; border.color: Atelier.container
                    Text { anchors.centerIn: parent; text: Profile.busy ? "…" : "󰄀"; font.family: Atelier.font; font.pixelSize: 14; color: Atelier.onFill }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Profile.pick() }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: Atelier.userName; elide: Text.ElideRight
                    font.family: Atelier.fontUi; font.pixelSize: 22; font.weight: Font.DemiBold; color: Atelier.text }
                Text { Layout.fillWidth: true; elide: Text.ElideRight
                    text: Profile.login + (Profile.host ? " @ " + Profile.host : "") + (Profile.realName && Profile.realName !== Atelier.userName ? "  ·  " + Profile.realName : "")
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsMd; color: Atelier.subtext }
                Text { Layout.fillWidth: true; Layout.topMargin: 4; wrapMode: Text.WordWrap
                    visible: Profile.error !== ""; text: Profile.error
                    font.family: Atelier.fontUi; font.pixelSize: Atelier.fsSm; color: Atelier.red }
                RowLayout {
                    Layout.topMargin: 10
                    spacing: 6
                    Chip { icon: "󰄀"; text: Profile.hasFace ? "Change picture" : "Add picture"; tint: Atelier.accent
                        interactive: !Profile.busy; implicitHeight: 30; onClicked: Profile.pick() }
                    Chip { visible: Profile.hasFace; icon: "󰆴"; text: "Remove"; tint: Atelier.red
                        interactive: !Profile.busy; implicitHeight: 30; onClicked: Profile.remove() }
                    Chip { visible: Profile.hasBackup; icon: "󰕌"; text: "Previous"; tint: Atelier.subtext
                        interactive: !Profile.busy; implicitHeight: 30; onClicked: Profile.restore() }
                }
            }
        }
    }

    SettingCard {
        title: "Name and greetings"
        SettingField { label: "Display name"; description: "Shown on the lock screen, desktop and Settings. Empty uses " + (Profile.realName ? "your full name" : "your login name")
            placeholder: Profile.realName || Profile.login
            text: Settings.general.userName; onCommitted: (t) => Settings.general.userName = t.trim() }
        SettingField { label: "Desktop greeting"; description: "Under the desktop clock. Empty = Good morning / afternoon / evening"
            placeholder: "By time of day"
            text: Settings.widgets.greetingText; onCommitted: (t) => Settings.widgets.greetingText = t.trim() }
        SettingField { label: "Login screen greeting"; description: "Above the clock on the login screen"
            placeholder: "By time of day"
            text: Settings.greeter.greeting; onCommitted: (t) => Settings.greeter.greeting = t.trim() }
    }

    SettingCard {
        title: "Account"
        SettingRow {
            label: "Login name"
            description: "Your Linux user. It can't be changed from here"
            Text { text: Profile.login; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.subtext1 }
        }
        SettingRow {
            label: "Full name"
            description: Profile.realName ? "Stored in your account (GECOS); other apps show it" : "Not set. Other apps show your login name"
            RowLayout {
                spacing: 8
                Text { visible: Profile.realName !== ""; text: Profile.realName; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.subtext1 }
                Chip { icon: "󰏫"; text: "Edit"; tint: Atelier.subtext; interactive: true; implicitHeight: 28
                    onClicked: Quickshell.execDetached([Settings.behavior.terminal, "-e", "sh", "-c",
                        "echo 'Change your full name: type it at the Name prompt, press Enter to keep the other fields.'; echo; chfn; echo; read -p 'Done. Press Enter to close' x"]) }
            }
        }
        SettingRow {
            label: "Computer name"
            description: "How this PC shows up on the network and in Bluetooth"
            RowLayout {
                spacing: 8
                Text { text: Profile.host; font.family: Atelier.fontUi; font.pixelSize: Atelier.fsLg; color: Atelier.subtext1 }
                Chip { icon: "󰏫"; text: "Rename"; tint: Atelier.subtext; interactive: true; implicitHeight: 28
                    onClicked: Quickshell.execDetached([Settings.behavior.terminal, "-e", "sh", "-c",
                        "printf 'New computer name: '; read n; [ -n \"$n\" ] && sudo hostnamectl hostname \"$n\"; echo; read -p 'Done. Press Enter to close' x"]) }
            }
        }
        SettingRow {
            label: "Login screen"
            description: Settings.greeter.autoSync ? "Your picture and greeting follow to the login screen automatically" : "Turn on syncing in Login screen to use this picture there too"
            Chip { icon: "󰅂"; text: "Open"; tint: Atelier.subtext; interactive: true; implicitHeight: 28; onClicked: win.page = "login" }
        }
    }
}
