pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Current wallpaper, rendered by Background.qml (replaces hyprpaper).
// Stored in ~/.cache/current_wallpaper so other tools (and the next login) see it.
Singleton {
    id: root

    property string current: ""
    // true while Background.qml animates a change: the theme regenerates afterwards, because
    // re-theming every app (and recolouring the shell) mid-animation makes it stutter
    property bool transitioning: false
    onTransitioningChanged: if (!transitioning && pendingTheme) themeDebounce.restart()
    property bool pendingTheme: false

    function set(path: string): void {
        if (!path || path === current) return;
        current = path;
        stateFile.setText(path);
    }

    // Keep the "Wallpaper Dark/Light" themes in step with the wallpaper: regenerate their palettes
    // (and re-apply if one is active). The script skips work when the image hasn't changed.
    onCurrentChanged: if (current) themeDebounce.restart()
    Timer {
        id: themeDebounce
        interval: 250
        onTriggered: {
            if (root.transitioning) { root.pendingTheme = true; return; }
            root.pendingTheme = false;
            if (!themeProc.running) themeProc.running = true;
        }
    }
    Process {
        id: themeProc
        command: [Quickshell.env("HOME") + "/.local/bin/atelier-theme", "wallpaper", root.current]
    }

    // ── next / previous / random, straight from a key (no picker) ──
    // The same folders the picker shows; the list is re-read each time, so new files count.
    property string stepMode: ""            // "next" | "prev" | "random" while listing
    function next(): void { stepMode = "next"; listProc.running = true; }
    function prev(): void { stepMode = "prev"; listProc.running = true; }
    function random(): void { stepMode = "random"; listProc.running = true; }
    Process {
        id: listProc
        command: ["sh", "-c", 'for d in "$HOME/.config/hypr/wall" "$HOME/Pictures/Wallpapers"; do [ -d "$d" ] && find -L "$d" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) -exec readlink -f {} +; done | sort -u']
        stdout: StdioCollector {
            onStreamFinished: {
                const all = text.trim().split("\n").filter(l => l);
                if (!all.length) return;
                const i = all.indexOf(root.current);
                let n;
                if (root.stepMode === "random") {
                    n = Math.floor(Math.random() * all.length);
                    if (all.length > 1 && n === i) n = (n + 1) % all.length;
                } else {
                    n = i < 0 ? 0 : (i + (root.stepMode === "prev" ? all.length - 1 : 1)) % all.length;
                }
                root.stepMode = "";
                root.set(all[n]);
            }
        }
    }

    FileView {
        id: stateFile
        path: Quickshell.env("HOME") + "/.cache/current_wallpaper"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const t = text().trim();
            if (t && t !== root.current) root.current = t;
        }
    }
}
