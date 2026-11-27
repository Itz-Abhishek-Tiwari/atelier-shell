pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Quick scratchpad: one plain-text note that is saved as you type (statePath scratchpad.txt),
// so it survives closing the drawer, shell reloads and logins.
//
//   qs ipc call scratchpad toggle | open | close | get | append "text" | clear
Singleton {
    id: root

    property string text: ""
    property bool loaded: false
    readonly property int words: { const t = text.trim(); return t === "" ? 0 : t.split(/\s+/).length; }

    function set(t: string): void {
        if (t === text) return;
        text = t;
        save.restart();
    }
    function append(t: string): void { set(text === "" || text.endsWith("\n") ? text + t : text + "\n" + t); }
    function clear(): void { set(""); }
    function copy(): void { if (text !== "") Quickshell.execDetached(["wl-copy", "--", text]); }

    Timer { id: save; interval: 400; onTriggered: file.setText(root.text) }
    FileView {
        id: file
        printErrors: false
        path: Quickshell.statePath("scratchpad.txt")
        onLoaded: { root.text = text(); root.loaded = true; }
        onLoadFailed: root.loaded = true
    }
}
