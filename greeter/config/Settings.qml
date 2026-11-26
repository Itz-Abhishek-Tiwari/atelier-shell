pragma Singleton
import QtQuick
import Quickshell
import qs.services

// Login-screen stand-in for the shell's Settings: the sections the lock styles read, from
// lock.json (greeter-sync.sh copies them out of ~/.config/atelier/settings.json). Read-only here.
Singleton {
    readonly property var lock: Object.assign({ theme: "atelier", clock: "system" }, GreeterData.s.lock || {})
    readonly property var lockStyle: Object.assign({ size: 0.72, cupertinoWeight: "bold", cupertinoTint: "white", cupertinoWidgets: true, cupertinoNotifs: "pile", hyperGradient: "accent", hyperWeight: "regular", hyperCards: true, harmonyCalendar: true, harmonyAccent: false, harmonyWeekStart: "mon", oxygenShelf: "bottom", oxygenAccent: "red", oxygenSeconds: false, materialLayout: "grid", materialShrink: true, dotColor: "white", dotSeconds: true, dotBackground: "mono" },
        GreeterData.s.lockStyle || {})
    readonly property var notifications: Object.assign({ lockShowCount: true }, GreeterData.s.notifications || {})
    readonly property var widgets: Object.assign({ weatherLocation: "", weatherUnits: "metric" }, GreeterData.s.widgets || {})
    readonly property var general: Object.assign({ clock24: false, userName: "", animSpeed: 1 }, GreeterData.s.general || {})
    readonly property var appearance: Object.assign({ rounding: 24 }, GreeterData.s.appearance || {})
}
