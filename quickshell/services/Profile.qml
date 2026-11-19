pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// The user's profile: picture (~/.face), login/real name, computer name.
// Settings → Profile edits it; the lock screens and the Settings sidebar show it.
// `faceUrl` carries a revision so every Image reloads the moment the picture changes
// (Qt caches images by URL).
Singleton {
    id: root

    readonly property string script: Quickshell.shellDir + "/scripts/avatar.py"
    property bool hasFace: false
    property int rev: 0
    readonly property string faceUrl: hasFace ? "file://" + Quickshell.env("HOME") + "/.face?r=" + rev : ""
    property string login: Quickshell.env("USER") || ""
    property string realName: ""
    property string host: ""
    property bool hasBackup: false
    property bool busy: false
    property string error: ""

    function refresh(): void { if (!infoProc.running) infoProc.running = true; }
    // file picker (zenity: GTK, follows the theme), then crop + save
    function pick(): void {
        if (busy || pickProc.running) return;
        error = "";
        pickProc.running = true;
    }
    function setFrom(path: string): void { run(["set", path]); }
    function remove(): void { run(["remove"]); }
    function restore(): void { run(["restore"]); }
    function run(args) {
        if (busy) return;
        busy = true;
        error = "";
        editProc.command = [script].concat(args);
        editProc.running = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: infoProc
        command: [root.script, "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.login = d.login || root.login;
                    root.realName = d.realName || "";
                    root.host = d.host || "";
                    root.hasBackup = !!d.hasBackup;
                    if (d.hasFace !== root.hasFace || d.faceMtime !== root.rev) {
                        root.hasFace = !!d.hasFace;
                        root.rev = d.faceMtime || 0;
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: pickProc
        command: ["zenity", "--file-selection", "--title=Choose a profile picture",
                  "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.gif *.bmp *.PNG *.JPG *.JPEG *.WEBP",
                  "--filename=" + Quickshell.env("HOME") + "/Pictures/"]
        stdout: StdioCollector {
            onStreamFinished: { const p = text.trim(); if (p) root.setFrom(p); }
        }
    }

    Process {
        id: editProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { const d = JSON.parse(text.trim().split("\n").pop()); if (!d.ok) root.error = d.error || "failed"; }
                catch (e) { root.error = "failed"; }
            }
        }
        onExited: {
            root.busy = false;
            root.refresh();
            Greeter.autoSync();          // the login screen shows the same picture
        }
    }
}
