pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.config

// Battery alerts (Settings → Power & battery → Battery):
//  - a notification at the low level and a critical one (stays, gets through Do Not Disturb)
//    at the critical level, once each per discharge; the critical one replaces the low one
//  - both are cleared as soon as the charger goes in
//  - a toast when the charger is plugged in or pulled out (shell.qml shows it)
Singleton {
    id: root

    signal toast(string msg, string icon, color clr)

    readonly property var dev: UPower.displayDevice
    readonly property bool present: !!dev && dev.ready && dev.isLaptopBattery
    readonly property int pct: present ? Math.round(dev.percentage * 100) : -1
    readonly property bool onBattery: UPower.onBattery

    // the lowest level already warned about in this discharge (101 = none yet)
    property int warned: 101

    function timeLeft(): string {
        const s = present ? dev.timeToEmpty : 0;
        if (!(s > 0)) return "";
        const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }

    function check(): void {
        if (!present || !Settings.battery.alerts) return;
        if (!onBattery) { warned = 101; clearWarnings(); return; }
        const crit = Settings.battery.critical, low = Settings.battery.low;
        if (pct <= crit && warned > crit) { warned = crit; send(true); }
        else if (pct <= low && warned > low) { warned = low; send(false); }
    }

    function send(critical: bool): void {
        const left = timeLeft();
        const about = left ? " (about " + left + ")" : "";
        Quickshell.execDetached(["notify-send", "-a", "Battery",
            "-i", critical ? "battery-caution" : "battery-low",
            "-u", critical ? "critical" : "normal",
            "-h", "string:x-dunst-stack-tag:atelier-battery",
            critical ? "Battery critically low" : "Battery low",
            critical ? root.pct + "% left" + about + ". Plug in now or the laptop will go to sleep."
                     : root.pct + "% left" + about + "."]);
    }

    function clearWarnings(): void {
        for (const n of Notifs.list.filter(x => x.appName === "Battery")) Notifs.dismiss(n);
    }

    Connections {
        target: root.dev
        function onPercentageChanged() { root.check(); }
    }
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            root.check();
            if (!root.present || !Settings.battery.chargerToast) return;
            if (root.onBattery) {
                const left = root.timeLeft();
                root.toast("On battery · " + root.pct + "%" + (left ? " · " + left : ""), "󰂃", Atelier.yellow);
            } else {
                root.toast("Charging · " + root.pct + "%", "󰂄", Atelier.green);
            }
        }
    }
    // already low at login: warn once things have settled
    Timer { running: true; interval: 4000; onTriggered: root.check() }
}
