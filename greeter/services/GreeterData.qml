pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Everything the login screen knows, read from its data folder (it runs as the `greeter` user
// and can't read your home). quickshell/scripts/greeter-sync.sh fills that folder:
//   colors.json   your theme              lock.json     your lock-screen options
//   wallpaper.jpg your wallpaper          depth.png/json  the Depth style's subject cut-out
//   faces/<user>  avatars                 fonts/        the clock font
// The lock styles (modules/lock, the same files as the shell's lock screen) read it through the
// small stand-ins in config/ and services/.
Singleton {
    id: root

    readonly property string dataDir: Quickshell.env("ATELIER_GREETER_DATA") || "/var/lib/atelier-greeter"

    // the person picked on the login screen (set by shell.qml)
    property string user: ""
    property string realName: ""

    // ── palette (a copy of ~/.config/atelier/theme.json) ──
    property var c: ({
        base: "#1e1e2e", mantle: "#181825", crust: "#11111b", surface0: "#313244", surface1: "#45475a",
        surface2: "#585b70", overlay0: "#6c7086", overlay1: "#7f849c", text: "#cdd6f4", subtext1: "#bac2de",
        subtext0: "#a6adc8", red: "#f38ba8", peach: "#fab387", yellow: "#f9e2af", green: "#a6e3a1",
        teal: "#94e2d5", sky: "#89dceb", sapphire: "#74c7ec", blue: "#89b4fa", lavender: "#b4befe",
        mauve: "#cba6f7", pink: "#f5c2e7", accent: "#cba6f7"
    })
    property bool isLight: false
    FileView {
        path: root.dataDir + "/colors.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = JSON.parse(text());
                const cols = Object.assign({}, root.c, t.colors || {});
                // the theme names its accent role ("accent": "mauve"); a colour also works
                if (!t.colors || !t.colors.accent) cols.accent = cols[t.accent] || (String(t.accent || "").startsWith("#") ? t.accent : cols.mauve);
                root.c = cols;
                root.isLight = t.variant === "light";
            } catch (e) { console.log("greeter: bad colors.json, using defaults"); }
        }
    }

    // ── your lock-screen options (a slice of ~/.config/atelier/settings.json) ──
    property var s: ({})
    FileView {
        path: root.dataDir + "/lock.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.s = JSON.parse(text()); } catch (e) { console.log("greeter: bad lock.json, using defaults"); } }
    }

    // ── the Depth style's cut-out for this wallpaper ──
    property var depth: ({})
    FileView {
        path: root.dataDir + "/depth.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { root.depth = JSON.parse(text()); } catch (e) { root.depth = {}; } }
    }

    // ── the clock font (SpaceMono, copied over once) ──
    FontLoader { id: monoR; source: "file://" + root.dataDir + "/fonts/mono-regular.ttf" }
    FontLoader { source: "file://" + root.dataDir + "/fonts/mono-bold.ttf" }
    readonly property string monoFont: monoR.status === FontLoader.Ready ? monoR.name : "JetBrainsMono Nerd Font"
}
