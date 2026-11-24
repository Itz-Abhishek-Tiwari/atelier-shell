import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Settings → Login screen (greetd greeter).
ColumnLayout {
    required property var win
    id: loginPage
    Layout.fillWidth: true
    spacing: 20
    readonly property bool shown: win.visible && win.page === "login"
    onShownChanged: if (shown) Greeter.refresh()
    Timer { interval: 3000; repeat: true; running: loginPage.shown; onTriggered: Greeter.refresh() }
    readonly property bool on: Greeter.writable

    SettingCard {
        title: "Login screen"; icon: "󰍂"; tint: Atelier.pink
        SettingRow {
            label: !Greeter.installed ? "Not installed"
                : Greeter.active ? "In use" : "Installed, not the login manager yet"
            description: !Greeter.installed ? "Installs greetd + cage and the Atelier greeter. Your current login manager stays until you switch."
                : Greeter.active ? "greetd shows the Atelier login screen at boot (it looks like your lock screen)."
                : "SDDM (or another manager) is still active. Switch when the preview looks right (password in the preview: demo)."
            RowLayout {
                spacing: 6
                Chip { icon: "󰈈"; text: "Preview"; tint: Atelier.pink; interactive: true; implicitHeight: 30
                    onClicked: Greeter.preview() }
                Chip { visible: !Greeter.installed; icon: "󰏔"; text: "Install"; tint: Atelier.green; interactive: true; implicitHeight: 30
                    onClicked: Greeter.runInstaller("") }
                Chip { visible: Greeter.installed && !Greeter.active; icon: "󰁔"; text: "Use at boot"; tint: Atelier.green; interactive: true; implicitHeight: 30
                    onClicked: Greeter.runInstaller("--enable") }
            }
        }
        SettingRow {
            visible: Greeter.installed && (!Greeter.upToDate || !Greeter.writable)
            label: "Update needed"
            description: !Greeter.writable
                ? "Run the installer once so Settings can control the login screen (it hands /var/lib/atelier-greeter to you)."
                : "The installed greeter is older than the one in your dotfiles (new design, no window buttons, no text after login)."
            Chip { icon: "󰚰"; text: "Update"; tint: Atelier.peach; interactive: true; implicitHeight: 30
                onClicked: Greeter.runInstaller("--refresh") }
        }
    }

    SettingCard {
        title: "Look"; icon: "󰕮"; tint: Atelier.mauve
        SettingRow {
            label: "Same as your lock screen"
            description: {
                const st = Settings.lockStyles.find(x => x.id === Settings.lock.theme) || Settings.lockStyles[0];
                return st.name + " · " + st.note + ". Change the style and its options on the Lock screen page; the login screen follows.";
            }
            Chip { icon: "󰌾"; text: "Lock screen"; tint: Atelier.mauve; interactive: true; implicitHeight: 30; onClicked: win.page = "lock" }
        }
        SettingRow {
            label: "Who and which desktop"
            description: "A small pill in the top-left corner: F1 switches the person, F2 the desktop session"
        }
    }

    SettingCard {
        title: "Sync"; icon: "󰑐"; tint: Atelier.sky
        enabled: loginPage.on; opacity: enabled ? 1 : 0.5
        SettingSwitch { label: "Follow your look"; description: "Copy your colours, wallpaper, lock style and ~/.face to the login screen whenever they change"; tint: Atelier.sky
            checked: Settings.greeter.autoSync; onToggled: (v) => { Settings.greeter.autoSync = v; if (v) Greeter.sync(); } }
        SettingRow {
            label: "Sync now"
            description: Greeter.syncing ? "Copying…"
                : Greeter.syncedAt > 0 ? "Last synced " + Qt.formatDateTime(new Date(Greeter.syncedAt * 1000), "d MMM, hh:mm")
                  + (Greeter.lastSyncResult ? "  ·  " + Greeter.lastSyncResult : "")
                : "Not synced yet"
            Chip { icon: "󰑐"; text: "Sync"; tint: Atelier.sky; interactive: !Greeter.syncing; implicitHeight: 30
                onClicked: Greeter.sync() }
        }
    }

    SettingCard {
        title: "Boot"; icon: "󰒓"; tint: Atelier.peach
        SettingRow {
            label: "Quiet boot"
            description: Greeter.quietBoot ? "On: kernel and systemd messages are hidden at boot."
                : "Off: kernel messages can show on the login screen's console. Adds “quiet loglevel=3” to /etc/kernel/cmdline and rebuilds the boot image (takes effect next boot)."
            Chip { visible: !Greeter.quietBoot; icon: "󰒓"; text: "Turn on"; tint: Atelier.peach; interactive: true; implicitHeight: 30
                onClicked: Greeter.runInstaller("--quiet-boot") }
        }
        SettingRow {
            label: "Switch back to SDDM"
            description: "Removes the Atelier greeter. If a login ever fails: Ctrl+Alt+F3, sign in, run greeter/install.sh --uninstall."
            Chip { visible: Greeter.active; icon: "󰜺"; text: "Uninstall"; tint: Atelier.red; interactive: true; implicitHeight: 30
                onClicked: Greeter.runInstaller("--uninstall") }
        }
    }
}
